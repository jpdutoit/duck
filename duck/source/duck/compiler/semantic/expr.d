module duck.compiler.semantic.expr;

import duck.compiler;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.overloads;
import duck.compiler.semantic.errors;
import duck.compiler.visitors;

struct ExprSemantic {
  SemanticAnalysis *semanticAnalysis;
  int pipeDepth = 0;

  alias semanticAnalysis this;

  E semantic(E)(E target) {
    E expr = target;
    semanticAnalysis.accept(expr);
    return expr;
  }

  E semantic(E)(ref E target) {
    semanticAnalysis.accept(target);
    return target;
  }

  Expr makeModule(Type type, Expr ctor) {
    auto decl = new VarDecl(type, Slice(), ctor);
    return new InlineDeclExpr(new DeclStmt(decl)).withSource(ctor);
  }

  bool implicitCall(ref Expr expr) {
    if (auto r = expr.as!RefExpr)
    if (r.isCallable) {
      if (auto callable = resolveCall(r, [])) {
        expr = callable.call().withSource(r);
        semantic(expr);
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
          semantic(expr);
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
            auto ctor = refExpr.call().withSource(expr);
            expr = makeModule(metaType, ctor);
            semantic(expr);
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

    if (sourceExpr.hasError || sourceType.isSameType(targetType)) return sourceExpr;

    // Coerce an overload set by automatically calling it
    if (sourceType.isCallable) {
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
      if (auto output = moduleType.members.reference(Slice("output"), sourceExpr)) {
        semantic(output.withSource(sourceExpr));
        return coerce(output, targetType);
      }
    }

    // Coerce bool by automatically converting it to int/float
    if (sourceExpr.type.as!BoolType && (targetType.as!IntegerType ||targetType.as!FloatType)) {
      auto castExpr = new CastExpr(sourceExpr, targetType);
      semantic(castExpr);
      return coerce(castExpr, targetType);
    }

    // Coerce int by automatically converting it to float
    if (sourceExpr.type.as!IntegerType && targetType.as!FloatType) {
      auto castExpr = new CastExpr(sourceExpr, targetType);
      semantic(castExpr);
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
    return new TupleExpr(output, parameterTypes);
  }

  RefExpr resolveCall(RefExpr reference, Expr[] arguments, CallableDecl[]* viable = null) {
    auto args = new TupleExpr(arguments);
    semantic(args);
    return resolveCall(reference, args, viable);
  }

  RefExpr resolveCall(RefExpr reference, TupleExpr arguments, CallableDecl[]* viable = null) {
    if (reference)
    if (auto overloadSet = reference.decl.as!OverloadSet) {
      auto best = findBestOverload(overloadSet, arguments, viable);
      if (best) {
        auto expr = best.reference().withSource(reference);
        expr.context = reference.context;
        return expr;
      }
    }
    return null;
  }

  Node visit(ErrorExpr expr) {
    return expr;
  }

  Node visit(InlineDeclExpr expr) {
    semantic(expr.declStmt);

    expr.declStmt.withSource(expr.source).insertBefore(this.stack.find!Stmt);
    debug(Semantic) log("=> Split", expr.declStmt);

    return semantic(expr.declStmt.decl.reference().withSource(expr.source));
    //Expr identExpr = new IdentifierExpr(expr).withSource(expr);
    //return semantic(identExpr);
  }

  Node visit(ArrayLiteralExpr expr) {
    Type elementType;
    foreach(ref e; expr.exprs) {
      semantic(e);
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
    semantic(expr.left);
    semantic(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    implicitConstructCall(expr.right);

    // Piping to a function is the same as calling that function
    if (expr.right.isCallable) {
      return semantic(expr.right.call([expr.left]));
    }

    Expr originalRHS = expr.right;
    expr.type = expr.right.type;

    while (expr.right.type.as!ModuleType && expr.right.isLValue) {
      expr.right = expr.right.member("input");
      semantic(expr.right);
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
      stmt.withSource(expr).insertBefore(this.stack.find!Stmt);
      return originalRHS;
    }

    return expr;
  }

  Node visit(CastExpr expr) {
    semantic(expr.expr);
    if (!expr.targetType) {
      expr.targetType = ErrorType.create;
    }
    expr.type = expr.targetType;

    if (expr.sourceType.as!IntegerType || expr.sourceType.as!FloatType || expr.sourceType.as!BoolType) {
      if (expr.targetType.as!IntegerType || expr.targetType.as!FloatType || expr.targetType.as!BoolType) {
        return expr;
      }
    }

    if (!expr.type.hasError && !expr.expr.type.hasError)
      expr.error("Cast from " ~ mangled(expr.expr.type) ~ " to " ~ mangled(expr.targetType) ~ " not allowed");

    return expr.taint;
  }

  Node visit(UnaryExpr expr) {
    if (semantic(expr.operand).hasError)
      return expr.taint;

    if (auto callable = resolveCall(symbolTable.reference(expr.operator), expr.arguments))
      return semantic(callable.call(expr.arguments).withSource(expr));

    return expr.operand.error("Operation " ~ expr.operator.value.idup ~ " " ~ mangled(expr.operand.type) ~ " is not defined.");
  }

  Node visit(BinaryExpr expr) {
    if (semantic(expr.left).hasError | semantic(expr.right).hasError)
      return expr.taint;

    if (auto callable = resolveCall(symbolTable.reference(expr.operator), expr.arguments))
      return semantic(callable.call(expr.arguments).withSource(expr));

    error(expr.operator, "Operation " ~ mangled(expr.left.type) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.type) ~ " is not defined.");
    return expr.taint;
  }

  Node visit(TupleExpr expr) {
    bool tupleError = false;
    Type[] elementTypes = [];
    elementTypes.length = expr.length;
    foreach (i, ref Expr e; expr) {
      if (semantic(e).hasError)
        tupleError = true;
      elementTypes[i] = e.type;
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
    return expansion;
  }

  Node visit(ConstructExpr expr) {
    if (semantic(expr.callable).hasError | semantic(expr.arguments).hasError)
      return expr.taint;

    TypeDecl decl = expr.callable.getTypeDecl();
    debug(Semantic) log("=> decl", decl);

    return expr.callable.type.visit!(
      // This part is only needed because sometimes semantic runs more than once on some nodes
      // TODO: Removed when this is fixed
      delegate(FunctionType ft) {
        expr.arguments = coerce(expr.arguments, ft.parameters);
        return expr;
      },

      delegate Expr(MetaType metaType) {
        auto members = decl.visit!(
          (StructDecl structDecl) => structDecl.members,
          (TypeDecl decl) => null
        );

        CallableDecl[] viable = [];
        auto ctors = members ? members.reference(Slice("__ctor")) : null;
        if (ctors) semantic(ctors);
        if (auto resolved = resolveCall(ctors, expr.arguments, &viable)) {
          expr.callable = resolved;
          semantic(expr.callable);
          expr.arguments = coerce(expr.arguments, resolved.type.enforce!FunctionType.parameters);
          expr.type = decl.declaredType;
          return expr;
        } else if (expr.arguments.length == 0 && !decl.as!ModuleDecl) {
          // TODO: Implement typedefs, then this no longer needs to allow structs
          // Default constructors for basic types
          expr.type = expr.callable.getTypeDecl().declaredType;
          expr.callable = null;
          return expr;
        } else if (expr.arguments.length == 1 && !decl.as!StructDecl) {
          auto castExpr = new CastExpr(expr.arguments[0], metaType.type);
          return semantic(castExpr);
        }

        return expr.errorResolvingConstructorCall(ctors, viable);
      }
    );
  }

  Node visit(IndexExpr expr) {
    semantic(expr.expr);
    semantic(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.expr.hasError || expr.arguments.hasError)
      return expr.taint;

    return expr.expr.type.visit!(
      (StructType t) {
        if (expr.expr.hasError) {
          expr.taint;
        }
        else {
          auto indexFn = t.members.reference(Slice("[]"), expr.expr);
          if (auto resolved = resolveCall(indexFn, expr.arguments)) {
            Expr expr = resolved.call(expr.arguments).withSource(expr);
            return semantic(expr);
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

        Expr re = arrayDecl.reference();
        re.type = t;
        return semantic(re);
      }
    );
  }

  Node visit(CallExpr expr) {
    semantic(expr.callable);
    debug(Semantic) log("=>", expr);
    pipeDepth++;
    semantic(expr.arguments);
    pipeDepth--;
    debug(Semantic) log("=>", expr);


    if (expr.callable.hasError || expr.arguments.hasError)
      return expr.taint;

    Node resolve(CallExpr expr) {
      return expr.callable.type.visit!(
        (MacroType type) {
          expr.arguments = coerce(expr.arguments, type.parameters);
          expr.type = type.returnType;
          auto callable = expr.callable.enforce!RefExpr;
          return expandMacro(type.decl, expr.arguments, callable.context).withSource(expr);
        },
        (FunctionType ft) {
          expr.arguments = coerce(expr.arguments, ft.parameters);
          expr.type = ft.returnType;
          return expr;
        },
        (OverloadSetType ot) {
          CallableDecl[] viable = [];
          auto overloadSet = expr.callable.enforce!RefExpr;
          auto resolved = resolveCall(overloadSet, expr.arguments, &viable);
          if (resolved) {
            expr.callable = semantic(resolved);
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
        (MetaType tt) {
          Expr expr = new ConstructExpr(expr.callable, expr.arguments, expr.source);
          return semantic(expr);
        },
        (Type tt) {
          return expr.error("Cannot call something with type " ~ mangled(expr.callable.type));
        }
      );
    }
    return resolve(expr);
  }

  Node visit(AssignExpr expr) {
    semantic(expr.left);
    implicitCall(expr.left);
    semantic(expr.right);
    implicitCall(expr.right);

    if (!expr.left.hasError && !expr.right.hasError)
      expr.right = coerce(expr.right, expr.left.type);

    if (expr.left.hasError || expr.right.hasError)
      return expr.taint;

    expr.type = expr.left.type;
    return expr;
  }

  Node visit(IdentifierExpr expr) {
    if (RefExpr reference = symbolTable.reference(expr.identifier)) {
      return semantic(reference);
    }

    return expr.error("Undefined identifier " ~ expr.identifier.idup);
  }

  Node visit(TypeExpr expr) {
      semantic(expr.expr);
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
      semantic(expr.context);
      debug(Semantic) log("=>", expr);
      implicitConstructCall(expr.context);
      if (expr.context.hasError) return expr.taint;
    }

    expr.type = expr.decl.type;
    return expr;
  }

  Node visit(MemberExpr expr) {
    semantic(expr.context);
    implicitConstructCall(expr.context);
    debug(Semantic) log("=>", expr);

    if (expr.context.hasError) return expr.taint;

    return expr.context.type.visit!(
      (StructType type) {
        auto contextRef = expr.context.as!RefExpr;
        if (auto reference = type.members.reference(expr.name, expr.context)) {
          // Only allow private members to be accessed through the context reference
          if (reference.decl.visibility == Visibility.private_
          && (!contextRef || contextRef.decl != type.decl.context))
            return expr.error("Cannot access private member `" ~ expr.name ~ "'");
          return semantic(reference.withSource(expr));
        }
        return expr.error("No member " ~ expr.name ~ " in " ~ type.decl.name);
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
