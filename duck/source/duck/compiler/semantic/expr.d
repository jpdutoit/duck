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

  E accept(E)(ref E target) {
    semantic.accept!E(target);
    return target;
  }

  Expr makeModule(Type type, Expr ctor) {
    auto decl = new VarDecl(type, context.temporary(), ctor);
    return new InlineDeclExpr(new DeclStmt(decl));
  }

  bool implicitCall(ref Expr expr) {
    if (auto r = expr.as!RefExpr)
    if (auto os = r.type.as!OverloadSetType) {
      if (auto callable = resolveCall(os.overloadSet, [])) {
        expr = callable.reference().withContext(r.context).withSource(r).call();
        accept(expr);
        return true;
      }
    }
    return false;
  }

  void implicitConstruct(ref Expr expr) {
    expr.visit!(
      delegate(ConstructExpr cexpr) {
        if (expr.type.as!ModuleType) {
          expr = makeModule(expr.type, expr);
          accept(expr);
        }
      },
      (Expr e) { }
    );
    expr.type.visit!(
      delegate(MetaType metaType) {
        // Rewrite: ModuleType
        // to:      ModuleType tmpVar = Module();
        if (auto refExpr = cast(RefExpr)expr) {
          if (metaType.type.as!ModuleType) {
            auto ctor = refExpr.call();
            expr = makeModule(metaType, ctor);
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
    if (auto metaType = cast(MetaType)type) {
      return "type " ~ metaType.type.describe;
    }
    return "a value of type " ~ type.describe;
  }

  Expr coerce(Expr sourceExpr, Type targetType) {
    debug(Semantic) log("=> coerce", sourceExpr.type.describe.green, "to", targetType.describe.green);
    auto sourceType = sourceExpr.type;

    if (sourceType.isSameType(targetType)) return sourceExpr;

    // Coerce an overload set by automatically calling it
    if (sourceType.as!OverloadSetType) {
      if (implicitCall(sourceExpr))
        return coerce(sourceExpr, targetType);
    }

    // Coerce type by constructing instance of that type
    if (auto metaType = sourceType.as!MetaType) {
      if (auto moduleType = metaType.type.as!ModuleType) {
        implicitConstruct(sourceExpr);
        return coerce(sourceExpr, targetType);
      }
    }
    // Coerce module by automatically reference field output
    if (auto moduleType = sourceType.as!ModuleType) {
      auto output = moduleType.decl.decls.lookup("output");
      if (output) {
        sourceExpr = sourceExpr.member("output");
        accept(sourceExpr);
        return coerce(sourceExpr, targetType);
      }
    }

    // Coerce int by automatically converting it to float
    if (sourceExpr.type.as!IntegerType && targetType.as!FloatType) {
      auto castExpr = new CastExpr(sourceExpr, targetType);
      accept(castExpr);
      return coerce(castExpr, targetType);
    }

    if (targetType.hasError || sourceType.hasError) return sourceExpr.taint;
    return sourceExpr.error("Cannot coerce " ~ describe(sourceType) ~ " to " ~ describe(targetType));
  }

  TupleExpr coerce(TupleExpr sourceExpr, TupleType parameterTypes) {
    Expr[] output;
    output.length = sourceExpr.length;

    bool error = false;
    foreach(i, parameter; sourceExpr) {
      output[i] = coerce(parameter, parameterTypes[i]);
      error |= output[i].hasError;
    }
    if (error) return sourceExpr.taint;

    auto result = new TupleExpr(output);
    accept(result);
    return result;
  }

  CallableDecl resolveCall(OverloadSet overloadSet, Expr[] arguments, Expr context = null, CallableDecl[]* viable = null) {
    TupleExpr args = new TupleExpr(arguments.dup);
    accept(args);
    auto best = findBestOverload(overloadSet, context, args, viable);
    return best;
  }

  CallableDecl resolveCall(SymbolTable searchScope, string identifier, Expr[] arguments, Expr context = null) {
    if (auto overloadSet = searchScope.lookup(identifier).decl.as!OverloadSet)
      return resolveCall(overloadSet, arguments);
    return null;
  }

  CallableDecl resolveCall(Scope searchScope, string identifier, Expr[] arguments, Expr context = null) {
    if (auto overloadSet = searchScope.lookup(identifier).as!OverloadSet)
      return resolveCall(overloadSet, arguments);
    return null;
  }

  Node visit(ErrorExpr expr) {
    return expr;
  }

  Node visit(InlineDeclExpr expr) {
    accept(expr.declStmt);

    splitStatement(expr.declStmt);
    debug(Semantic) log("=> Split", expr.declStmt);

    Expr ident = new IdentifierExpr(expr).withSource(expr);
    accept(ident);
    return ident;
  }

  Node visit(ArrayLiteralExpr expr) {
    Type elementType;
    foreach(ref e; expr.exprs) {
      accept(e);
      if (!elementType) {
        elementType = e.type;
      } else if (elementType != e.type) {
        e = coerce(e, elementType);
      }
    }
    expr.type = ArrayType.create(expr.exprs[0].type);
    return expr;
  }

  Node visit(PipeExpr expr) {
    pipeDepth++;
    accept(expr.left);
    accept(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    implicitConstructCall(expr.right);

    // Piping to a function is the same as calling that function
    if (auto os = expr.right.type.as!OverloadSetType) {
      Expr call = expr.right.call([expr.left]);
      accept(call);
      return call;
    }

    Expr originalRHS = expr.right;
    expr.type = expr.right.type;

    while (expr.right.type.as!ModuleType && expr.right.isLValue) {
      expr.right = expr.right.member("input");
      accept(expr.right);
      implicitCall(expr.right);
      debug(Semantic) log("=>", expr);
    }

    expr.left = coerce(expr.left, expr.right.type);
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

  Node visit(CastExpr expr) {
    accept(expr.expr);
    if (!expr.targetType) {
      expr.targetType = ErrorType.create;
    }
    expr.type = expr.targetType;

    if (expr.sourceType.as!IntegerType || expr.sourceType.as!FloatType) {
      if (expr.targetType.as!IntegerType || expr.targetType.as!FloatType) {
        return expr;
      }
    }

    if (!expr.type.hasError && !expr.expr.type.hasError)
      expr.error("Cast from " ~ mangled(expr.expr.type) ~ " to " ~ mangled(expr.targetType) ~ " not allowed");

    return expr.taint;
  }

  Node visit(UnaryExpr expr) {
    accept(expr.operand);

    if (expr.operand.hasError) return expr.taint;

    auto callable = resolveCall(symbolTable, expr.operator, expr.arguments);
    if (callable) {
      Expr e = callable.call(expr.arguments).withSource(expr);
      return accept(e);
    }

    return expr.operand.error("Operation " ~ expr.operator.value.idup ~ " " ~ mangled(expr.operand.type) ~ " is not defined.");
  }

  Node visit(BinaryExpr expr) {
    accept(expr.left);
    accept(expr.right);

    if (expr.left.hasError || expr.right.hasError) {
      expr.taint;
    }
    else {
      auto callable = resolveCall(symbolTable, expr.operator, expr.arguments);
      if (callable) {
        Expr e = callable.call(expr.arguments).withSource(expr);
        return accept(e);
      }
    }

    auto call = new ErrorExpr(expr.operator).taint.call(expr.arguments);
    if (!expr.hasError)
      call.error("Operation " ~ mangled(expr.left.type) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.type) ~ " is not defined.");

    return call.taint;
  }

  Node visit(TupleExpr expr) {
    bool tupleError = false;
    Type[] elementTypes = [];
    assumeSafeAppend(elementTypes);
    foreach (ref Expr e; expr) {
      accept(e);
      if (e.hasError)
        tupleError = true;
      elementTypes ~= e.type;
    }
    if (tupleError) return expr.taint;
    expr.type = TupleType.create(elementTypes);
    return expr;
  }

  Expr expandMacro(CallableDecl macroDecl, Expr[] arguments, Expr contextExpr = null) {
    debug(Semantic) log("=> ExpandMacro", macroDecl, contextExpr);

    Expr[Decl] replacements;
    foreach (i, parameter; macroDecl.parameters) {
      replacements[parameter] = arguments[i];
    }
    if (macroDecl.parentDecl)
      replacements[macroDecl.parentDecl.context] = contextExpr;

    Expr expansion = macroDecl.returnExpr;
    if (expansion.hasError) return expansion;

    debug(Semantic) log("=> expansion", expansion);
    expansion = expansion.dupWithReplacements(replacements);
    debug(Semantic) log("=> expansion", expansion);
    accept(expansion);

    return expansion;
  }

  Node visit(ConstructExpr expr) {
    accept(expr.callable);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    TypeDecl decl = expr.callable.getTypeDecl();

    debug(Semantic) log("=> decl", decl);
    if (expr.callable.hasError || expr.arguments.hasError)
      return expr.taint;

    //TODO: Generate default constructor if no constructors are defined.

    return expr.callable.type.visit!(
      delegate(FunctionType ft) {
        expr.arguments = coerce(expr.arguments, ft.parameters);
        return expr;
      },

      delegate(MetaType metaType) {
        if (expr.arguments.length == 1 && expr.arguments[0].type == metaType.type) {
          return expr.arguments[0];
        }

        return decl.visit!(
          (StructDecl structDecl) {
            // TODO: Rewrite as call expression instead
            OverloadSet os = structDecl.ctors;
            expr.context = structDecl.reference().withSource(expr);
            accept(expr.context);

            auto best = resolveCall(os, expr.arguments.elements, expr.context);
            if (best) {
              expr.arguments = coerce(expr.arguments, best.type.parameters);
              expr.type = decl.declaredType;
              // Expand macros immediately
              if (best.isMacro) {
                return expandMacro(best, expr.arguments.elements, expr.context);
              }

              expr.callable = best.reference();
              accept(expr.callable);
              return expr;
            }
            else {
              if (expr.arguments.length == 0) {
                expr.type = expr.callable.getTypeDecl().declaredType;
                expr.callable = null;
                return expr;
              }
              return expr.error("No constructor matches argument types " ~ expr.arguments.type.describe());
            }
          },
          (TypeDecl typeDecl) {
            expr.type = expr.callable.getTypeDecl().declaredType;
            expr.callable = null;
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

    return expr.expr.type.visit!(
      (StructType t) {
        if (expr.expr.hasError) {
          expr.taint;
        }
        else {
          auto callable = resolveCall(t.decl.decls, "[]", expr.arguments.elements);
          if (callable) {
            Expr e = callable.reference().withContext(expr.expr).call(expr.arguments).withSource(expr);
            return accept(e);
          }
        }
        if (!expr.hasError)
          expr.error("Cannot index type " ~ mangled(expr.expr.type) ~ " with " ~ mangled(expr.arguments.type) ~ ".");
        return expr;
      },
      (StaticArrayType t) {
        if (expr.arguments.length != 1) {
          expr.arguments.error("Only one index accepted");
          return expr.taint;
        }
        expr.type = t.elementType;
        return expr;
      },
      (ArrayType t) {
        if (expr.arguments.length != 1) {
          expr.arguments.error("Only one index accepted");
          return expr.taint;
        }
        expr.type = t.elementType;
        return expr;
      },
      (MetaType t) {
        TypeDecl decl = expr.expr.getTypeDecl;
        debug(Semantic) log ("=>", decl);
        ArrayDecl arrayDecl;

        if (expr.arguments.length == 0)
          arrayDecl = new ArrayDecl(decl);
        else {
          if (expr.arguments.length != 1) {
            expr.arguments.error("Only one length accepted.");

            return expr.taint;
          }
          import std.conv: to;
          auto size = expr.arguments[0].visit!(
              (LiteralExpr literal) => literal.value.toString().to!uint,
              (Expr e) {
                expr.arguments.error("Expected a number for array size.");
                expr.taint;
                return cast(uint)0;
              }
          )();
          if (expr.hasError) return expr;

          arrayDecl = new ArrayDecl(decl, size);
        }

        auto re = arrayDecl.reference();
        re.type = t;
        accept(re);
        return re.as!Expr;
      }
    );
  }

  Node visit(CallExpr expr) {
    accept(expr.callable);
    debug(Semantic) log("=>", expr);
    pipeDepth++;
    accept(expr.arguments);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    if (expr.callable.hasError || expr.arguments.hasError)
      return expr.taint;

    if (!expr.context) {
      expr.context = expr.callable.visit!(
        (RefExpr expr) => expr.context,
        (Expr expr) => null
      );
    }

    Node resolve(CallExpr expr) {
      return expr.callable.type.visit!(
        delegate (FunctionType ft) {
          expr.arguments = coerce(expr.arguments, ft.parameters);
          expr.type = ft.returnType;
          auto callable = expr.callable.enforce!RefExpr().decl.as!CallableDecl;
          if (callable.isMacro) {
            return expandMacro(callable, expr.arguments.elements, expr.context);
          }
          return expr;
        },
        delegate (OverloadSetType ot) {
          debug(Semantic) log("=>", "context", expr.context);

          CallableDecl[] viable = [];
          auto best = resolveCall(ot.overloadSet, expr.arguments.elements, expr.context, &viable);
          if (best) {
            auto r = expr.callable.enforce!RefExpr;
            expr.callable = best.reference().withContext(r.context).withSource(r);
            accept(expr.callable);
            return resolve(expr);
          }
          else {
            CallableDecl[] candidates;
            if (viable.length == 0) {
              if (ot.overloadSet.decls.length > 1)
                error(expr, "No function matches arguments:");
              else
                error(expr, "Function does not match arguments:");
              candidates = ot.overloadSet.decls;
            }
            else {
              error(expr, "Multiple functions matches arguments:");
              candidates = viable;
            }
            foreach(CallableDecl callable; candidates) {
              info(callable.headerSource, "  " ~ callable.headerSource);
            }
            return expr.taint;
          }
        },
        delegate (MetaType tt) {
          Expr e = new ConstructExpr(expr.callable, expr.arguments, null, expr.source);
          accept(e);
          return e;
        },
        delegate (Type tt) {
          return expr.error("Cannot call something with type " ~ mangled(expr.callable.type));
        }
      );
    }
    return resolve(expr);
  }

  Node visit(AssignExpr expr) {
    //TODO: Type check
    accept(expr.left);
    implicitCall(expr.left);
    debug(Semantic) log("=>", expr);
    accept(expr.right);
    implicitCall(expr.right);
    debug(Semantic) log("=>", expr);
    expr.type = expr.left.type;
    return expr;
  }

  Node visit(IdentifierExpr expr) {
    ContextDecl decl = symbolTable.lookup(expr.identifier);

    if (decl) {
      auto reference = decl.reference()
        .withContext(decl.context)
        .withSource(expr);
      accept(reference);
      return reference;
    }

    return expr.error("Undefined identifier " ~ expr.identifier.idup);
  }

  Node visit(TypeExpr expr) {
      accept(expr.expr);
      debug(Semantic) log("=>", expr.expr);

      if (auto re = cast(RefExpr)expr.expr) {
        if (expr.expr.type.as!MetaType && re.decl.as!TypeDecl) {
          expr.type = expr.expr.type;
          expr.decl = re.decl.as!TypeDecl;
          return expr;
        }
      }

      if (!expr.expr.hasError) {
        expr.decl = new TypeDecl(ErrorType.create());
        expr.error("Expected a type");
      }
      return expr.taint();
  }

  Node visit(RefExpr expr) {
    if (expr.context) {
      accept(expr.context);
      debug(Semantic) log("=>", expr);
      implicitConstructCall(expr.context);
      if (expr.context.hasError) return expr.taint;
    }

    expr.type = expr.decl.type;
    return expr;
  }

  Node visit(MemberExpr expr) {
    accept(expr.context);
    implicitConstructCall(expr.context);
    debug(Semantic) log("=>", expr);

    if (expr.context.hasError) return expr.taint;

    return expr.context.type.visit!(
      (StructType type) {
        auto member = type.decl.decls.lookup(expr.name);
        if (!member) {
          return expr.error("No member " ~ expr.name ~ " in " ~ type.decl.name);
        }

        auto refExpr = member.reference().withContext(expr.context).withSource(expr);
        return accept(refExpr);
      },
      (Type t) {
        expr.context.error("Cannot access members of " ~ expr.context.type.mangled());
        return expr.taint;
    });
  }

  // Nothing to do for these
  Node visit(LiteralExpr expr) {
    return expr;
  }
}
