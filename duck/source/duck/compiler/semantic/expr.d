module duck.compiler.semantic.expr;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.ast;
import duck.compiler.scopes;
import duck.compiler.lexer;
import duck.compiler.types;
import duck.compiler.visitors;
import duck.compiler.dbg;

struct ExprSemantic {
  SemanticAnalysis *semantic;
  int pipeDepth = 0;

  alias semantic this;

  void accept(E)(ref E target) { semantic.accept!E(target); }

  Expr makeModule(Type type, Expr ctor) {
    auto t = context.temporary();
    return new InlineDeclExpr(t, new VarDeclStmt(t, new VarDecl(type, t), ctor));
  }

  void implicitCall(ref Expr expr) {
    expr.exprType.visit!(
      delegate(OverloadSetType os) {
        expr = new CallExpr(expr, new TupleExpr([]));
        accept(expr);
      },
      (Type type) { }
    );
  }

  void implicitMember(ref Expr expr, string member) {
    expr = new MemberExpr(expr, context.token(Identifier, member));
    accept(expr);
    implicitCall(expr);
  }

  void implicitConstruct(ref Expr expr) {
    expr.exprType.visit!(
      delegate(TypeType t) {
        // Rewrite: ModuleType
        // to:      ModuleType tmpVar = Module();
        if (auto refExpr = cast(RefExpr)expr) {
          if (refExpr.decl.declType.isKindOf!ModuleType) {
            auto ctor = new CallExpr(refExpr, new TupleExpr([]));
            expr = makeModule(refExpr.decl.declType, ctor);
            accept(expr);
            return;
          }
        }
      },
      delegate(ModuleType t) {
        // Rewrite: Expr that returns a ModuleType temporary
        // to:      ModuleType tmpVar = expr;
        if (!expr.isLValue) {
          expr = makeModule(expr.exprType, expr);
          accept(expr);
        }
      },
      delegate(Type type) {}
    );
  }

  void implicitConstructCall(ref Expr expr) {
    implicitConstruct(expr);
    implicitCall(expr);
  }

  Node visit(ErrorExpr expr) {
    return expr;
  }

  Node visit(InlineDeclExpr expr) {
    accept(expr.declStmt);

    splitStatement(expr.declStmt);
    debug(Semantic) log("=> Split", expr.declStmt);
    Expr ident = new IdentifierExpr(expr.token);
    accept(ident);
    return ident;
  }

  Node visit(ArrayLiteralExpr expr) {
    Type elementType;
    foreach(ref e; expr.exprs) {
      accept(e);
      if (!elementType) {
        elementType = e.exprType;
      } else if (elementType != e.exprType) {
        error(e, "Expected array element to have type " ~ elementType.mangled);
      }
    }
    expr.exprType = ArrayType.create(expr.exprs[0].exprType);
    return expr;
  }

  Node visit(PipeExpr expr) {
    debug(Semantic) log("PipeExpr", "depth =", pipeDepth);
    debug(Semantic) log("=>", expr);
    pipeDepth++;
    accept(expr.left);
    accept(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    implicitConstructCall(expr.left);
    implicitConstructCall(expr.right);

    debug(Semantic) log("=>", expr);

    Expr originalRHS = expr.right;


    while (expr.right.isModule && expr.right.isLValue) {
      expr.exprType = expr.right.exprType;
      implicitMember(expr.right, "input");
      debug(Semantic) log("=>", expr);
    }
    while (isModule(expr.left) && isLValue(expr.left)) {
      implicitMember(expr.left, "output");
      debug(Semantic) log("=>", expr);
    }
    {
      if (!expr.left.hasError && !expr.right.hasError) {
        if (expr.left.exprType.kind == TypeType.Kind) {
          expr.taint;
          error(expr.left, "expected a value expression");
        }
        if (expr.right.exprType.kind == TypeType.Kind) {
          expr.taint;
          Decl decl = expr.right.getTypeDecl;
          error(expr.right, "Type " ~ mangled(decl ? decl.declType : expr.right.exprType) ~ " is not a valid connection target");
        }
        if (!isLValue(expr.right)) {
          expr.taint;
          error(expr.right, "Cannot connect to an expression");
        }
        if (expr.left.exprType != expr.right.exprType && !expr.hasError) {
          error(expr, "cannot connect a " ~ mangled(expr.left.exprType) ~ " to a " ~ mangled(expr.right.exprType) ~ " input");
        }
      }
      if (!expr.exprTypeSet)
         expr.exprType = expr.right.exprType;
    }

    if (pipeDepth > 0) {
      Stmt stmt = new ExprStmt(expr);
      debug(Semantic) log("=> Split", expr);
      splitStatement(stmt);
      //pipeDepth = pd;
      return originalRHS;
    }

    return expr;
  }

  Node visit(BinaryExpr expr) {
    TupleExpr args = new TupleExpr([expr.left, expr.right]);
    accept(args);

    while (isModule(args[0])) {
      implicitMember(args[0], "output");
    }
    while (isModule(args[1])) {
      implicitMember(args[1], "output");
    }
    args.exprType = args.tupleType();

    expr.left = args[0];
    expr.right = args[1];
    auto os = cast(OverloadSet)semantic.symbolTable.lookup(expr.operator.value);
    if (os && !args.hasError) {
      CallableDecl[] viable;
      auto best = findBestOverload(os, null, args, &viable);
      if (best) {
        if (!best.external) {
          Expr e = new CallExpr(new RefExpr(expr.operator, best), args);
          accept(e);
          return e;
        }
        expr.exprType = best.getResultType();
        return expr;
      }
    }

    if (!args[0].hasError && !args[1].hasError)
      error(expr.left, "Operation " ~ mangled(expr.left.exprType) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.exprType) ~ " is not defined.");
    return expr.taint();
  }

  Node visit(TupleExpr expr) {
    bool tupleError = false;
    Type[] elementTypes = [];
    assumeSafeAppend(elementTypes);
    foreach (ref Expr e; expr) {
      accept(e);
      if (e.hasError)
        tupleError = true;
      else {
        implicitConstructCall(e);
      }
      elementTypes ~= e.exprType;
    }
    if (tupleError) return expr.taint;

    expr.exprType = TupleType.create(elementTypes);
    return expr;
  }

  Expr expandMacro(MacroDecl macroDecl, Expr contextExpr) {
    debug(Semantic) log("=> ExpandMacro", macroDecl, contextExpr);

    Scope macroScope = new DeclTable();
    symbolTable.pushScope(macroScope);
    macroScope.define("this", new AliasDecl(context.token(Identifier, "this"), contextExpr));

    debug(Semantic) log("=> expansion", macroDecl.expansion);
    Expr expansion = macroDecl.expansion.dupl();
    debug(Semantic) log("=> expansion", expansion);
    accept(expansion);

    debug(Semantic) log("=>", expansion);

    symbolTable.popScope();

    return expansion;
  }

  Node visit(ConstructExpr expr) {
    accept(expr.expr);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    Decl decl = expr.expr.getTypeDecl();

    debug(Semantic) log("=> decl", decl);
    if (expr.expr.hasError || expr.arguments.hasError) {
      return expr.taint;
    }

    //TODO: Generate default constructor if no constructors are defined.
    if (expr.arguments.length == 0) {
      expr.exprType = expr.expr.getTypeDecl().declType;
      return expr;
    }

    return expr.expr.exprType.visit!(
      delegate(TypeType type) {
        if (expr.arguments.length == 1 && expr.arguments[0].exprType == decl.declType) {
          return expr.arguments[0];
        }

        return decl.visit!(
          (StructDecl structDecl) {

            OverloadSet os = structDecl.ctors;
            Expr contextExpr = new RefExpr(structDecl.name, decl);
            accept(contextExpr);
            CallableDecl[] viable;
            CallableDecl best = findBestOverload(os, contextExpr, expr.arguments, &viable);

            if (viable.length > 0) {
              this.error(expr, "Ambigious call.");
              expr.taint;
              return expr;
            }
            else if (best) {
              expr.exprType = decl.declType;
              debug(Semantic) log("=> best overload", best);

              // Expand macros immediately
              if (auto macroDecl = cast(MacroDecl)best) {
                return expandMacro(macroDecl, contextExpr);
              }

              return expr;
            }
            else {
              this.error(expr, "No constructor matches argument types " ~ expr.arguments.exprType.describe());
              expr.taint();
              return expr;
            }
          },
          (TypeDecl typeDecl) {
            return expr;
          }
        );
      },
      (Node node) {
        return null;
      }
    );
  }

  Node visit(IndexExpr expr) {
    accept(expr.expr);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.expr.hasError || expr.arguments.hasError) {
      return expr.taint;
    }

    return expr.expr.exprType.visit!(
      (StaticArrayType t) {
        if (expr.arguments.length != 1) {
          this.error(expr.arguments, "Only one index accepted");
          return expr.taint;
        }
        expr.exprType = t.elementType;
        return expr;
      },
      (ArrayType t) {
        if (expr.arguments.length != 1) {
          this.error(expr.arguments, "Only one index accepted");
          return expr.taint;
        }
        expr.exprType = t.elementType;
        return expr;
      },
      (TypeType t) {
        Decl decl = expr.expr.getTypeDecl;
        debug(Semantic) log ("=>", decl);
        ArrayDecl arrayDecl;

        if (expr.arguments.length == 0)
          arrayDecl = new ArrayDecl(decl.declType);
        else {
          if (expr.arguments.length != 1) {
            this.error(expr.arguments, "Only one length accepted.");

            return expr.taint;
          }
          import std.conv: to;
          auto size = expr.arguments[0].visit!(
              (LiteralExpr literal) => literal.token.toString().to!uint,
              (Expr e) {
                this.error(expr.arguments, "Expected a number for array size.");
                expr.taint;
                return cast(uint)0;
              }
          )();
          if (expr.hasError) return expr;

          arrayDecl = new ArrayDecl(decl.declType, size);
        }

        auto re = new RefExpr(this.context.token(Identifier, "this"), arrayDecl);
        re.exprType = t;
        accept(re);
        return re;
      }
    );

  }

  Node visit(CallExpr expr) {
    accept(expr.expr);
    debug(Semantic) log("=>", expr);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.expr.hasError || expr.arguments.hasError) {
      return expr.taint;
    }

    return expr.expr.exprType.visit!(
      delegate (OverloadSetType ot) {
        OverloadSet os = ot.overloadSet;

        Expr contextExpr;
        expr.expr.visit!(
          delegate (MemberExpr expr) {
            contextExpr = expr.left;
          },
          (Expr expr) { }
        );

        debug(Semantic) log("=>", "context", contextExpr);
        CallableDecl[] viable;
        CallableDecl best = findBestOverload(os, contextExpr, expr.arguments, &viable);

        if (viable.length > 0) {
          this.error(expr, "Ambigious call.");
          expr.taint;
          return expr;
        }
        else if (best) {
          expr.exprType = (cast(FunctionType)best.declType).returnType;
          debug(Semantic) log("=> best overload", best);

          // Expand macros immediately
          if (auto macroDecl = cast(MacroDecl)best) {
            return expandMacro(macroDecl, contextExpr);
          }

          return expr;
        }
        else {
          this.error(expr, "No functions matches arguments.");
          expr.taint();
          return expr;
        }
      },
      delegate (TypeType tt) {
        Expr e = new ConstructExpr(expr.expr, expr.arguments);
        accept(e);
        return e;

        /*Node n = new MemberExpr(expr.expr, context.token(Identifier, "constructor"));
        accept(n);
        return n;*/

        // Call constructor
        /*if (auto refExpr = cast(RefExpr)expr.expr) {
          expr.exprType = refExpr.decl.declType;
        }
        return expr;*/
      },
      delegate (Type tt) {
        if (!expr.expr.hasError)
          this.error(expr, "Cannot call something with type " ~ mangled(expr.expr.exprType));
        return expr.taint;
      }
    );
  }

  Node visit(AssignExpr expr) {
    //TODO: Type check
    accept(expr.left);
    implicitCall(expr.left);
    debug(Semantic) log("=>", expr);
    accept(expr.right);
    implicitCall(expr.right);
    debug(Semantic) log("=>", expr);
    expr.exprType = expr.left.exprType;
    return expr;
  }

  Node visit(UnaryExpr expr) {
    accept(expr.operand);
    implicitConstructCall(expr.operand);
    debug(Semantic) log("=>", expr);

      if (isModule(expr.operand)) {
        expr.operand = new MemberExpr(expr.operand, context.token(Identifier, "output"));
        accept(expr.operand);
        implicitCall(expr.operand);
      }
    {
      auto os = cast(OverloadSet)symbolTable.lookup(expr.operator.value);
      if (os) {
        TupleExpr args = new TupleExpr([expr.operand]);
        accept(args);

        if (!args.hasError) {
          CallableDecl[] viable;
          auto best = findBestOverload(os, null, args, &viable);

          if (best) {
            if (!best.external) {
              Expr e = new CallExpr(new RefExpr(expr.operator, best), args);
              accept(e);
              return e;
            }
            expr.exprType = best.getResultType();
            return expr;
          }
        }
      }

      if (!expr.operand.hasError)
        error(expr.operand, "Operation " ~ expr.operator.value.idup ~ " " ~ mangled(expr.operand.exprType) ~ " is not defined.");
      return expr.taint();
    }
  }

  Node visit(IdentifierExpr expr) {
    // Look up identifier in symbol table
    Decl decl = symbolTable.lookup(expr.identifier);
    if (!decl) {
      if (!expr.hasError) {
        error(expr, "Undefined identifier " ~ expr.identifier.idup);
        expr.taint;
      }
      return expr;
    } else {
      Expr resolve(Decl decl) {
        return decl.visit!(
          (OverloadSet overloadSet) {
            // TODO: This is a hack!!
            if (overloadSet.decls.length == 1 && cast(MacroDecl)overloadSet.decls[0]) {
              return resolve(overloadSet.decls[0]);
            }
            return new RefExpr(expr.token, overloadSet);
          },
          (MethodDecl methodDecl)
            => new MemberExpr(new IdentifierExpr(this.context.token(Identifier, "this")), expr.dupl()),
          (FieldDecl fieldDecl)
            => new MemberExpr(new IdentifierExpr(this.context.token(Identifier, "this")), expr.dupl()),
          (MacroDecl macroDecl)
            => new MemberExpr(new IdentifierExpr(this.context.token(Identifier, "this")), expr.dupl()),
          (AliasDecl aliasDecl)
            => aliasDecl.targetExpr,
          (UnboundDecl unboundDecl) {
            expr.exprType = unboundDecl.declType;
            return expr;
          },
          (Decl decl) => new RefExpr(expr.token, decl)
        );
      }

      auto result = resolve(decl);
      if (result != expr)
        accept(result);
      return result;
    }
  }

  Node visit(TypeExpr expr) {
      accept(expr.expr);
      debug(Semantic) log("=>", expr.expr);

      if (auto re = cast(RefExpr)expr.expr) {
        if (expr.expr.exprType.isKindOf!TypeType && cast(TypeDecl)re.decl) {
          expr.exprType = TypeType.create;
          expr.decl = cast(TypeDecl)re.decl;
          return expr;
        }
      }

      if (!expr.expr.hasError)
        error(expr, "Expected a type");
      return expr.taint();
  }

  Node visit(RefExpr expr) {
    //Decl decl = currentScope.lookup(expr.identifier.value);
    Decl decl = expr.decl;

    auto retExpr = decl.visit!(
      (TypeDecl decl) => (expr.exprType = TypeType.create, expr),
      (VarDecl decl) => (expr.exprType = decl.declType, expr),
      (MethodDecl decl) => (expr.exprType = decl.declType, expr),
      (FunctionDecl decl) => (expr.exprType = decl.declType, expr),
      (OverloadSet os) => (expr.exprType = OverloadSetType.create(os), expr),
      //(UnboundDecl decl) => (expr.exprType = decl.declType, expr),
      (AliasDecl decl) => decl.targetExpr
    );
    return retExpr;
  }

  Node visit(MemberExpr expr) {
    accept(expr.left);
    implicitConstructCall(expr.left);
    debug(Semantic) log("=>", expr);

    if (expr.left.hasError) return expr.taint;

    if (auto ge = cast(ModuleType)expr.left.exprType) {
      StructDecl decl = ge.decl;
      ASSERT(isLValue(expr.left), "Modules can not be temporaries.");

      auto structDecl = cast(StructDecl)decl;
      auto ident = expr.right.visit!((IdentifierExpr e) => e.identifier);
      auto fieldDecl = structDecl.decls.lookup(ident);

      if (fieldDecl) {
        expr.exprType = fieldDecl.declType;

        return expr;
      }
      error(expr, "No field " ~ ident.idup ~ " in " ~ structDecl.name.value.idup);
      return expr.taint;
    }

    error(expr.left, "Cannot access members of " ~ mangled(expr.left.exprType));
    return expr.taint;
  }

  // Nothing to do for these
  Node visit(LiteralExpr expr) {
    return expr;
  }
}
