module duck.compiler.semantic.expr;

import std.range.primitives;
import duck.compiler;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.overloads;
import duck.compiler.semantic.errors;
import duck.compiler.visitors;

//import std.conv: to;
import std.format: format;

struct ExprSemantic {
  SemanticAnalysis *semanticAnalysis;
  int pipeDepth = 0;

  alias semanticAnalysis this;

  E semantic(E: Node)(E target) {
    E expr = target;
    semanticAnalysis.accept(expr);
    return expr;
  }

  E semantic(E: Node)(ref E target) {
    semanticAnalysis.accept(target);
    return target;
  }

  void semantic(R)(R targets)
    if (isInputRange!R && is(ElementType!R: Node))
  {
    foreach (ref target; targets.save) {
      semanticAnalysis.accept(target);
    }
  }

  Expr makeModule(Type type, Expr ctor) {
    auto decl = new VarDecl(type, Slice(), ctor);
    return new InlineDeclExpr(new DeclStmt(decl)).withSource(ctor);
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

  Expr coerce(Expr sourceExpr, Type targetType) {
    debug(Semantic) log("=> coerce", sourceExpr.type.describe.green, "to", targetType.describe.green);
    auto sourceType = sourceExpr.type;

    if (sourceExpr.hasError || sourceType.isSameType(targetType)) return sourceExpr;

    // Coerce tuple
    if (auto sourceTuple = sourceExpr.as!TupleExpr)
      if (auto targetTypeTuple = targetType.as!TupleType)
        if (sourceTuple.length == targetTypeTuple.length) {
          Expr[] output;
          output.length = sourceTuple.length;

          bool error = false;
          foreach(i, parameter; sourceTuple) {
            output[i] = coerce(parameter, targetTypeTuple[i]);
            error |= output[i].hasError;
          }
          if (error) return sourceTuple.taint;
          return new TupleExpr(output, targetTypeTuple);
        }

    if (auto property = sourceType.as!PropertyType) {
      auto getters = lookup(sourceExpr, "get");
      if (auto resolved = getters.resolve) {
        Expr expr = resolved.call();
        return coerce(semantic(expr), targetType);
      }
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
      if (auto resolved = lookup!isValueLike(sourceExpr, "output").resolve()) {
        return coerce(semantic(resolved.withSource(sourceExpr)), targetType);
      }
    }

    // Coerce bool by automatically converting it to int/float
    if (sourceExpr.type.as!BoolType && (targetType.as!IntegerType ||targetType.as!FloatType)) {
      auto castExpr = new CastExpr(sourceExpr, targetType).withSource(sourceExpr.source);
      semantic(castExpr);
      return coerce(castExpr, targetType);
    }

    // Coerce int by automatically converting it to float
    if (sourceExpr.type.as!IntegerType && targetType.as!FloatType) {
      auto castExpr = new CastExpr(sourceExpr, targetType).withSource(sourceExpr.source);
      semantic(castExpr);
      return coerce(castExpr, targetType);
    }

    // Coerce static array to dynamic array
    if (auto sourceArray = sourceExpr.type.as!StaticArrayType)
    if (auto targetArray = targetType.as!ArrayType)
    if (sourceArray.elementType.isSameType(targetArray.elementType)) {
      auto castExpr = new CastExpr(sourceExpr, targetType).withSource(sourceExpr.source);
      semantic(castExpr);
      return coerce(castExpr, targetType);
    }

    if (targetType.hasError || sourceType.hasError) return sourceExpr.taint;
    return sourceExpr.coercionError(targetType);
  }

  Node visit(ErrorExpr expr) {
    return expr;
  }

  Node visit(InlineDeclExpr expr) {
    semantic(expr.declStmt);

    expr.declStmt.withSource(expr.source).insertBefore(this.stack.find!Stmt);
    debug(Semantic) log("=> Split", expr.declStmt);

    return semantic(expr.declStmt.decl.reference(null).withSource(expr.source));
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
    expr.type = StaticArrayType.create(expr.exprs[0].type, cast(uint)expr.exprs.length);
    return expr;
  }

  Node visit(PipeExpr expr) {
    pipeDepth++;
    semantic(expr.left);
    semantic(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    implicitConstruct(expr.right);

    // Piping to a function is the same as calling that function
    if (expr.right.isCallable) {
      return semantic(expr.right.call([expr.left]));
    }

    Expr originalRHS = expr.right;
    expr.type = expr.right.type;

    while (expr.right.type.as!ModuleType && expr.right.isLValue) {
      expr.right = expr.right.member("input");
      semantic(expr.right);
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

    auto sourceType = expr.sourceType;
    if (auto distinctType = sourceType.as!DistinctType)
      sourceType = distinctType.baseType;

    auto targetType = expr.targetType;
    if (auto distinctType = targetType.as!DistinctType)
      targetType = distinctType.baseType;

    if (sourceType.as!IntegerType || sourceType.as!FloatType || sourceType.as!BoolType) {
      if (targetType.as!IntegerType || targetType.as!FloatType || targetType.as!BoolType) {
        return expr;
      }
    }

    if (auto source = sourceType.as!StaticArrayType) {
      if (auto target = targetType.as!ArrayType) {
        if (source.elementType == target.elementType) {
          return expr;
        }
      }
    }

    if (!expr.type.hasError && !expr.expr.type.hasError)
      expr.error("Cast from " ~ mangled(expr.expr.type) ~ " to " ~ mangled(expr.targetType) ~ " not allowed");

    return expr.taint;
  }

  Node visit(UnaryExpr expr) {
    semantic(expr.operand);
    if (resolveValue(expr.operand).hasError)
      return expr.taint;

    CallableDecl[] viable;
    foreach (stage; symbolTable.stagedLookup(expr.operator)) {
      semantic(stage);
      if (auto best = findBestOverload(stage, expr.arguments, &viable))
        return semantic(stage.reference(best).call(expr.arguments).withSource(expr));

      if (viable.length > 0) {
        return error(expr, "Multiple overloads match arguments:", viable);
      }
    }

    return expr.operand.error("Operation " ~ expr.operator.value.idup ~ " " ~ mangled(expr.operand.type) ~ " is not defined.");
  }

  Node visit(BinaryExpr expr) {
    semantic(expr.left);
    semantic(expr.right);
    if (resolveValue(expr.left).hasError | resolveValue(expr.right).hasError)
      return expr.taint;

    CallableDecl[] viable;

    foreach (stage; symbolTable.stagedLookup(expr.operator)) {
      semantic(stage);
      if (auto best = findBestOverload(stage, expr.arguments, &viable))
        return semantic(stage.reference(best).call(expr.arguments).withSource(expr));

      if (viable.length > 0) {
        return error(expr, "Multiple overloads match arguments:", viable);
      }
    }

    error(expr.operator, "Operation " ~ mangled(expr.left.type) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.type) ~ " is not defined.");
    return expr.taint;
  }

  Expr resolveValue(ref Expr expr) {
    if (auto propertyType = expr.type.as!PropertyType) {
      expr = new MemberExpr(expr, "get", expr.source).call();
      expr = semantic(expr);
      return resolveValue(expr);
    }

    auto orType = expr.type.as!UnresolvedType;
    if (!orType) return expr;

    // If it contains a simple value, use that
    if (auto properties = orType.lookup.filtered!isValue) {
      if (auto property = properties.resolve) {
        return expr = semantic(property.withSource(expr));
      }
      return expr.error("Ambiguous value:", properties);
    }

    return expr.error("Ambiguous value:", orType.lookup);
  }

  Node visit(TupleExpr expr) {
    bool tupleError = false;
    Type[] elementTypes = [];
    elementTypes.length = expr.length;
    foreach (i, ref Expr e; expr) {
      semantic(e);
      resolveValue(e);
      if (e.hasError)
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
    if (auto structDecl = macroDecl.parent.as!StructDecl) {
      // TODO: Is this safe?
      replacements[structDecl.context.elements[0]] = contextExpr;
    }

    Expr expansion = macroDecl.returnExpr;
    if (expansion.hasError) return expansion;

    debug(Semantic) log("=> expansion", expansion);
    expansion = expansion.dupWithReplacements(replacements);
    debug(Semantic) log("=> expansion", expansion);
    return expansion;
  }

  Expr expandAlias(AliasDecl aliasDecl, Expr contextExpr = null) {
    debug(Semantic) log("=> ExpandAlias", aliasDecl, contextExpr);

    Expr[Decl] replacements;
    if (auto structDecl = aliasDecl.parent.as!StructDecl) {
      // TODO: Is this safe?
      replacements[structDecl.context.elements[0]] = contextExpr;
    }

    Expr expansion = aliasDecl.value;
    if (expansion.hasError) return expansion;

    debug(Semantic) log("=> expansion", expansion);
    expansion = expansion.dupWithReplacements(replacements);
    debug(Semantic) log("=> expansion", expansion);
    return expansion;
  }

  Node visit(ConstructExpr expr) {
    if (semantic(expr.callable).hasError | semantic(expr.arguments).hasError)
      return expr.taint;
    auto type = expr.callable.type.enforce!MetaType.type;
    auto ctors = lookup(expr.callable, Slice("__ctor"));
    CallableDecl[] viable;
    if (ctors) {
      semantic(ctors);
      if (auto best = findBestOverload(ctors, expr.arguments, &viable)) {
        expr.callable = best.reference(null);
        semantic(expr.callable);
        expr.arguments = coerce(expr.arguments, best.type.enforce!FunctionType.parameterTypes).as!TupleExpr;
        expr.type = type;
        return expr;
      }
    }

    if (expr.arguments.length == 0 && !type.as!ModuleType) {
      // TODO: Implement typedefs, then this no longer needs to allow structs
      // Default constructors for basic types
      expr.type = type;
      expr.callable = null;
      return expr;
    } else if (expr.arguments.length == 1 && !type.as!StructType) {
      Expr castExpr = new CastExpr(expr.arguments[0], type).withSource(expr.source);
      return semantic(castExpr);
    }

    return expr.errorResolvingConstructorCall(ctors.decls, viable);
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
          if (auto lookup = lookup(expr.expr, "[]")) {
            semantic(lookup);
            if (auto best = findBestOverload(lookup, expr.arguments))
              return semantic(lookup.reference(best).call(expr.arguments).withSource(expr).as!Expr);
          }
        }
        return expr.error("Cannot index type " ~ mangled(expr.expr.type) ~ " with " ~ mangled(expr.arguments.type) ~ ".");
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
        ArrayDecl arrayDecl;

        if (expr.arguments.length == 0)
          arrayDecl = new ArrayDecl(t.type);
        else {
          if (expr.arguments.length != 1) {
            expr.arguments.error("Only one length accepted.");

            return expr.taint;
          }
          import std.conv: to;
          auto size = expr.arguments[0].visit!(
              (IntegerValue integer) => integer.value,
              (Expr e) {
                expr.arguments.error("Expected a number for array size.");
                expr.taint;
                return cast(uint)0;
              }
          )();
          if (expr.hasError) return expr;

          arrayDecl = new ArrayDecl(t.type, size);
        }

        Expr re = arrayDecl.reference(null);
        return semantic(re);
      },
      (Type T) {
        expr.error("Cannot index type " ~ T.describe());
        return expr.taint;
      }
    );
  }

  Expr findImplicitContext(RefExpr expr, Decl decl) {
    //log("Looking for", decl, "in", expr);
    //log("", expr.contexts);
    auto value = decl in expr.contexts;
    if (value) return *value;
    if (auto next = expr.context.as!RefExpr) {
      return findImplicitContext(next, decl);
    }
    return null;
  }

  TupleExpr findImplicitContexts(Expr expr, ParameterList parameters) {
    auto refExpr = expr.enforce!RefExpr;
    Expr[] values;
    values.length = parameters.length - 1;
    Type[] types;
    types.length = parameters.length - 1;
    foreach (size_t i, ValueDecl decl; parameters.elements[1..$]) {
      auto value = findImplicitContext(refExpr, decl);

      if (value) {
        types[i] = value.type;
        values[i] = value;
      } else {
        expr.error("Internal compiler error: Missing context: " ~ decl.name);
      }
    }
    auto tupleExpr = new TupleExpr(values, TupleType.create(types));
    return tupleExpr;
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
        (FunctionType ft) {
          import std.range: only;
          if (!findBestOverload(only(ft.decl), expr.arguments, null)) {
            return expr.error("Function does not match arguments:", only(ft.decl));
          }
          expr.arguments = coerce(expr.arguments, ft.parameterTypes).as!TupleExpr;
          expr.type = ft.returnType;
          if (auto parentStruct = ft.decl.parent.as!StructDecl)
            expr.context = findImplicitContexts(expr.callable, parentStruct.context);
          if (ft.as!MacroType) {
            auto callable = expr.callable.enforce!RefExpr;
            return expandMacro(ft.decl, expr.arguments, callable.context).withSource(expr);
          }
          return expr;
        },
        (UnresolvedType ot) {
          CallableDecl[] viable = [];
          auto best = findBestOverload(ot.lookup, expr.arguments, &viable);
          if (best) {
            expr.callable = semantic(ot.lookup.reference(best).withSource(expr.callable));
            return resolve(expr);
          }
          return expr.errorResolvingCall(ot.lookup, viable);
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
    semantic(expr.right);
    resolveValue(expr.right);

    if (expr.left.hasError || expr.right.hasError)
      return expr.taint;

    if (auto propertyType = expr.left.type.as!PropertyType) {
      return semantic((new MemberExpr(expr.left, "set", expr.left.source)).call([expr.right]).withSource(expr));
    }

    expr.right = coerce(expr.right, expr.left.type);
    if (expr.right.hasError) return expr.taint;

    if (!expr.left.isLValue) {
      expr.left.error("Left hand side of assignment must be a l-value");
      return expr.taint;
    }

    expr.type = expr.left.type;
    return expr;
  }

  Node visit(IdentifierExpr expr) {
    foreach (stage; symbolTable.stagedLookup(expr.identifier)) {
      semantic(stage);

      if (auto resolved = stage.resolve) {
        return semantic(resolved.withSource(expr));
      }

      expr.type = UnresolvedType.create(stage);
      return expr;
    }
    return expr.error("Undefined identifier " ~ expr.identifier.idup);
  }

  Node visit(RefExpr expr) {
    if (expr.context) {
      semantic(expr.context);
      implicitConstruct(expr.context);
      if (expr.context.hasError) return expr.taint;
    }

    foreach(decl, ref value; expr.contexts) {
      semantic(value);
      implicitConstruct(value);
      if (value.hasError) return expr.taint;
    }

    semantic(expr.decl);

    if (auto aliasDecl = expr.decl.as!AliasDecl) {
      return expandAlias(aliasDecl, expr.context);
    }

    expr.type = expr.decl.type;
    return expr;
  }

  Node visit(MemberExpr expr) {
    semantic(expr.context);
    implicitConstruct(expr.context);
    debug(Semantic) log("=>", expr);

    if (expr.context.hasError) return expr.taint;

    return expr.context.type.visit!(
      (StructType type) {
        if (auto lookup = lookup(expr.context, expr.name, this.accessLevel(type))) {
          semantic(lookup);
          if (auto resolved = lookup.resolve())
            return semantic(resolved.withSource(expr));

          expr.type = UnresolvedType.create(lookup);
          return expr;
        }
        return expr.memberNotFoundError();
      },
      (ArrayType type) {
        if (expr.name == "size") {
          auto reference = new RefExpr(context.library.arraySizeDecl, expr.context);
          return semantic(reference.withSource(expr));
        }
        return expr.memberNotFoundError();
      },
      (StaticArrayType type) {
        if (expr.name == "size") {
          return semantic(new IntegerValue(type.size).withSource(expr));
        }
        return expr.memberNotFoundError();
      },
      (MetaType type) {
        if (auto structType = type.type.as!StructType)
        if (auto lookup = lookup(expr.context, expr.name, this.accessLevel(structType))) {
          semantic(lookup);
          if (auto resolved = lookup.resolve())
            return semantic(resolved.withSource(expr));

          expr.type = UnresolvedType.create(lookup);
          return expr;
        }
        return expr.memberNotFoundError();
      },
      (Type t) => expr.memberNotFoundError()
    );
  }

  // Nothing to do for these
  Node visit(LiteralExpr expr) {
    return expr;
  }
}
