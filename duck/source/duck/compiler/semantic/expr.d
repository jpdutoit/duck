module duck.compiler.semantic.expr;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.overloads;
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

  void implicitConstruct(ref Expr expr) {
    expr.visit!(
      delegate(ConstructExpr cexpr) {
        if (expr.isModule) {
          expr = makeModule(expr.exprType, expr);
          accept(expr);
        }
      }
    );
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
      delegate(Type type) {}
    );
  }

  void implicitConstructCall(ref Expr expr) {
    implicitConstruct(expr);
    implicitCall(expr);
  }

  string describe(Type type) {
    if (auto typeType = cast(TypeType)type) {
      return "type " ~ typeType.type.describe;
    }
    return "a value of type " ~ type.describe;
  }

  Expr coerce(Expr sourceExpr, Type targetType) {
    debug(Semantic) log("=> coerce", sourceExpr.exprType.describe.green, "to", targetType.describe.green);
    auto sourceType = sourceExpr.exprType;

    if (sourceType.isSameType(targetType)) return sourceExpr;

    // Coerce an overload set by automatically calling it
    if (auto overloadSetType = cast(OverloadSetType)sourceType) {
      implicitCall(sourceExpr);
      return coerce(sourceExpr, targetType);
    }
    // Coerce type by constructing instance of that type
    if (auto typeType = cast(TypeType)sourceType) {
      if (auto moduleType = cast(ModuleType)typeType.type) {
        implicitConstruct(sourceExpr);
        return coerce(sourceExpr, targetType);
      }
    }
    // Coerce module by automatically reference field output
    if (auto moduleType = cast(ModuleType)sourceType) {
      auto output = moduleType.decl.decls.lookup("output");
      if (output) {
        sourceExpr = new MemberExpr(sourceExpr, context.token(Identifier, "output"));
        accept(sourceExpr);
        return coerce(sourceExpr, targetType);
      }
    }
    return sourceExpr.error("Cannot coerce " ~ describe(sourceType) ~ " to " ~ describe(targetType));
  }

  bool coerce(Expr[] sourceExpr, CallableDecl targetDecl, ref Expr[] output) {
    auto target = targetDecl.parameterTypes;

    bool error = false;
    for (int i = 0; i < sourceExpr.length; ++i) {
      auto targetType = target[i].getTypeDecl.declType;
      output[i] = coerce(sourceExpr[i], targetType);
      error = error || output[i].hasError;
    }
    return !error;
  }

  bool coerce(Expr[] sourceExpr, CallableDecl targetDecl) {
    return coerce(sourceExpr, targetDecl, sourceExpr);
  }

  TupleExpr coerce(TupleExpr sourceExpr, CallableDecl targetDecl) {
    Expr[] output;
    output.length = sourceExpr.length;
    if (coerce(sourceExpr.elements, targetDecl, output)) {
      auto result = new TupleExpr(output);
      accept(result);
      return result;
    } else {
      sourceExpr.taint;
      return sourceExpr;
    }
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
        e.error("Expected array element to have type " ~ elementType.mangled);
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

    implicitConstructCall(expr.right);

    debug(Semantic) log("=>", expr);

    Expr originalRHS = expr.right;
    expr.exprType = expr.right.exprType;

    while (expr.right.isModule && expr.right.isLValue) {
      expr.right = new MemberExpr(expr.right, context.token(Identifier, "input"));
      accept(expr.right);
      implicitCall(expr.right);
      debug(Semantic) log("=>", expr);
    }

    expr.left = coerce(expr.left, expr.right.exprType);
    if(!expr.left.hasError)
      expect(isPipeTarget(expr.right), expr.right, "Right hand side of connection must be a module field");

    if (expr.left.hasError || expr.right.hasError) expr.taint;

    if (pipeDepth > 0) {
      Stmt stmt = new ExprStmt(expr);
      debug(Semantic) log("=> Split", expr);
      splitStatement(stmt);
      return originalRHS;
    }

    return expr;
  }

  CallableDecl resolveCall(Expr expr, Scope searchScope, Token identifier, Expr[] arguments, Expr context = null) {
    return resolveCall(expr, cast(OverloadSet)searchScope.lookup(identifier.value), arguments);
  }

  CallableDecl resolveCall(Expr expr, OverloadSet overloadSet, Expr[] arguments, Expr context = null) {
    if (!overloadSet) return null;

    TupleExpr args = new TupleExpr(arguments.dup);
    accept(args);
    CallableDecl[] viable;
    auto best = findBestOverload(overloadSet, context, args, &viable);
    if (expect(viable.length == 0, expr, "Ambigious call.") && best) {
      return best;
    }
    return null;
  }

  Expr call(Expr expr, CallableDecl callable, Expr[] arguments, Expr context = null) {
    coerce(arguments, callable);
    expr.exprType = (cast(FunctionType)callable.declType).returnType;

    return callable.visit!(
      (MacroDecl m) => expandMacro(m, arguments, context),
      (CallableDecl c) =>
        expr.visit!(
          (CallExpr e) => e,
          (Expr e) => e
        )
      );
  }

  Node visit(UnaryExpr expr) {
    accept(expr.operand);

    if (expr.operand.hasError) return expr.taint;

    auto callable = resolveCall(expr, symbolTable, expr.operator, expr.arguments);
    if (callable && coerce(expr.arguments, callable)) {
      if (!callable.external) {
        Expr e = new CallExpr(new RefExpr(expr.operator, callable), expr.arguments.dup);
        accept(e);
        return e;
      }
      expr.exprType = callable.getResultType();
      return expr;
    }

    return expr.operand.error("Operation " ~ expr.operator.value.idup ~ " " ~ mangled(expr.operand.exprType) ~ " is not defined.");
  }

  Node visit(BinaryExpr expr) {
    accept(expr.left);
    accept(expr.right);
    if (expr.left.hasError || expr.right.hasError)
      return expr.taint;

    auto callable = resolveCall(expr, symbolTable, expr.operator, expr.arguments);
    if (callable && coerce(expr.arguments, callable)) {
      if (!callable.external) {
        Expr e = new CallExpr(new RefExpr(expr.operator, callable), expr.arguments.dup);
        accept(e);
        return e;
      }
      expr.exprType = callable.getResultType();
      return expr;
    }

    return expr.left.error("Operation " ~ mangled(expr.left.exprType) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.exprType) ~ " is not defined.");
  }

  Node visit(TupleExpr expr) {
    bool tupleError = false;
    Type[] elementTypes = [];
    assumeSafeAppend(elementTypes);
    foreach (ref Expr e; expr) {
      accept(e);
      if (e.hasError)
        tupleError = true;
      elementTypes ~= e.exprType;
    }
    if (tupleError) return expr.taint;

    expr.exprType = TupleType.create(elementTypes);
    return expr;
  }

  Expr expandMacro(MacroDecl macroDecl, Expr[] arguments, Expr contextExpr = null) {
    debug(Semantic) log("=> ExpandMacro", macroDecl, call);

    Scope macroScope = new DeclTable();
    symbolTable.pushScope(macroScope);
    macroScope.define("this", new AliasDecl(context.token(Identifier, "this"), contextExpr));
    foreach (int i, Token paramName; macroDecl.parameterIdentifiers) {
      macroScope.define(paramName, new AliasDecl(paramName, arguments[i]));
    }

    debug(Semantic) log("=> expansion", macroDecl.expansion);
    Expr expansion = macroDecl.expansion.dup;
    debug(Semantic) log("=> expansion", expansion);
    accept(expansion);

    debug(Semantic) log("=>", expansion);

    symbolTable.popScope();

    return expansion;
  }

  Node visit(ConstructExpr expr) {
    typeCheck(expr.target);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    Decl decl = expr.target.getTypeDecl();

    debug(Semantic) log("=> decl", decl);
    if (expr.target.hasError || expr.arguments.hasError)
      return expr.taint;

    //TODO: Generate default constructor if no constructors are defined.
    if (expr.arguments.length == 0) {
      expr.exprType = expr.callable.getTypeDecl().declType;
      return expr;
    }

    return expr.target.exprType.visit!(
      delegate(TypeType type) {
        if (expr.arguments.length == 1 && expr.arguments[0].exprType == decl.declType) {
          return expr.arguments[0];
        }

        return decl.visit!(
          (StructDecl structDecl) {
            // TODO: Rewrite as call expression instead
            OverloadSet os = structDecl.ctors;
            expr.context = new RefExpr(structDecl.name, decl);
            accept(expr.context);

            auto best = resolveCall(expr, os, expr.arguments.elements, expr.context);
            if (best) {
              expr.arguments = coerce(expr.arguments, best);
              expr.exprType = decl.declType;
              // Expand macros immediately
              if (auto macroDecl = cast(MacroDecl)best) {
                return expandMacro(macroDecl, expr.arguments.elements, expr.context);
              }
              return expr;
            }
            else {
              return expr.error("No constructor matches argument types " ~ expr.arguments.exprType.describe());
            }
          },
          (TypeDecl typeDecl) {
            return expr;
          }
        );
      }
    );
  }

  Node visit(IndexExpr expr) {
    accept(expr.expr);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.expr.hasError || expr.arguments.hasError)
      return expr.taint;

    return expr.expr.exprType.visit!(
      (StaticArrayType t) {
        if (expr.arguments.length != 1) {
          expr.arguments.error("Only one index accepted");
          return expr.taint;
        }
        expr.exprType = t.elementType;
        return expr;
      },
      (ArrayType t) {
        if (expr.arguments.length != 1) {
          expr.arguments.error("Only one index accepted");
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
            expr.arguments.error("Only one length accepted.");

            return expr.taint;
          }
          import std.conv: to;
          auto size = expr.arguments[0].visit!(
              (LiteralExpr literal) => literal.token.toString().to!uint,
              (Expr e) {
                expr.arguments.error("Expected a number for array size.");
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
    typeCheck(expr.callable);
    debug(Semantic) log("=>", expr);
    if (!expr.arguments.exprTypeSet)
      accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.callable.hasError || expr.arguments.hasError)
      return expr.taint;

    if (!expr.context) {
      expr.context = expr.expr.visit!(
        (MemberExpr expr) => expr.left,
      );
    }
    return expr.expr.exprType.visit!(
      delegate (FunctionType ft) {
        //FIXME: Currently never reaches here yet
        expr.arguments = coerce(expr.arguments, ft.decl);
        expr.exprType = ft.returnType;
        return ft.decl.visit!(
          (MacroDecl m) => expandMacro(m, expr.arguments.elements, expr.context),
          (CallableDecl c) => expr
        );
      },
      delegate (OverloadSetType ot) {
        debug(Semantic) log("=>", "context", expr.context);

        auto best = resolveCall(expr, ot.overloadSet, expr.arguments.elements, expr.context);
        if (expect(best, expr, "No functions matches arguments.")) {
          expr.arguments = coerce(expr.arguments, best);
          expr.exprType = (cast(FunctionType)best.declType).returnType;
          debug(Semantic) log("=> best overload", best);

          // Expand macros immediately
          if (auto macroDecl = cast(MacroDecl)best) {
            return expandMacro(macroDecl, expr.arguments.elements, expr.context);
          }
        }
        return expr;
      },
      delegate (TypeType tt) {
        Expr e = new ConstructExpr(expr.expr, expr.arguments);
        accept(e);
        return e;
      },
      delegate (Type tt) {
        return expr.error("Cannot call something with type " ~ mangled(expr.expr.exprType));
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

  Node visit(IdentifierExpr expr) {
    // Look up identifier in symbol table
    Decl decl = symbolTable.lookup(expr.identifier);
    if (!decl) {
      if (!expr.hasError) {
        return expr.error("Undefined identifier " ~ expr.identifier.idup);
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
            => new MemberExpr(new IdentifierExpr(this.context.token(Identifier, "this")), expr.dup),
          (FieldDecl fieldDecl)
            => new MemberExpr(new IdentifierExpr(this.context.token(Identifier, "this")), expr.dup),
          (MacroDecl macroDecl) {
            if (macroDecl.parentDecl)
              return cast(Expr)new MemberExpr(new IdentifierExpr(this.context.token(Identifier, "this")), expr.dup);
            else
              return cast(Expr)new RefExpr(expr.token, decl);
          },
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
          expr.exprType = expr.expr.exprType;
          expr.decl = cast(TypeDecl)re.decl;
          return expr;
        }
      }

      if (!expr.expr.hasError)
        expr.error("Expected a type");
      return expr.taint();
  }

  Node visit(RefExpr expr) {
    //Decl decl = currentScope.lookup(expr.identifier.value);
    Decl decl = expr.decl;

    auto retExpr = decl.visit!(
      (TypeDecl decl) => (expr.exprType = TypeType.create(decl.declType), expr),
      (VarDecl decl) => (expr.exprType = decl.declType, expr),
      (CallableDecl decl) => (expr.exprType = decl.declType, expr),
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

      auto ident = expr.right.visit!((IdentifierExpr e) => e);
      auto fieldDecl = decl.decls.lookup(ident.identifier);

      if (fieldDecl) {
        expr.exprType = fieldDecl.declType;

        return expr;
      }
      expr.error("No field " ~ ident.identifier.idup ~ " in " ~ decl.name.value.idup);
      return expr.taint;
    }

    expr.left.error("Cannot access members of " ~ mangled(expr.left.exprType));
    return expr.taint;
  }

  // Nothing to do for these
  Node visit(LiteralExpr expr) {
    return expr;
  }
}
