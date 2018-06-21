module duck.compiler.semantic.helpers;

import duck.compiler;
import duck.compiler.visitors;
import duck.compiler.scopes;

import std.stdio;
import std.range;
public import std.range.primitives;
import std.algorithm.iteration;

enum isDeclRange(R) = (isInputRange!R && is(ElementType!R: Decl));

bool isCallable(Type type) {
  return type.visit!(
    (UnresolvedType o) => o.lookup.filtered!(isCallable).count == o.lookup.count,
    (FunctionType o) => true,
    (Type t) => false
  );
}

bool isCallable(Expr e) {
  return e.type.isCallable;
}

bool isValueLike(Decl d) {
  return d.type.visit!(
    (FunctionType t) => t.parameterTypes.length == 0,
    (MetaType t) => false,
    (Type t) => true
  );
}

bool isValue(Decl d) {
  return d.type.visit!(
    (FunctionType t) => false,
    (MetaType t) => false,
    (Type t) => true
  );
}

import std.meta: staticMap;


bool isCallable(Decl decl) { return decl.as!CallableDecl !is null; }
struct CallableRecognizer(flags...) {
  int parameters;

  this(int parameters) {
    this.parameters = parameters;
  }

  bool opCall(Decl decl) {
    if (auto callable = decl.as!CallableDecl) {
      if (parameters >= 0 && callable.parameters.length != parameters)
        return false;
      static foreach(flag; flags) {
        if (!mixin("callable." ~ flag)) return false;
      }
      return true;
    }
    return false;
  }
}

auto isConstructor(int parameters = -1) {
  return CallableRecognizer!"isConstructor"(parameters);
}

auto isCallable(int parameters) {
  return CallableRecognizer!()(parameters);
}

bool isLValue(Expr expr) {
  return expr.visit!(
    (IndexExpr i) => isLValue(i.expr),
    (IdentifierExpr i) => true,
    (RefExpr r) {
      if (r.context)
        return isLValue(r.context);
      return r.decl.visit!(
        (VarDecl d) => true,
        (ParameterDecl d) => true,
        (Decl d) => false
      );
    },
    (Expr _) => false
  );
}

bool isPipeTarget(Expr expr) {
  return expr.visit!(
    (IndexExpr i) => isPipeTarget(i.expr),
    (IdentifierExpr i) => true,
    (RefExpr r) => r.context && r.context.type.as!ModuleType && r.decl.as!VarDecl,
    (Expr e) => false
  );
}

enum MatchResult {
  Equal,
  Better,
  Worse
}

bool isFunctionViable(Type[] args, FunctionType A) {
  return false;
}

/*
http://en.cppreference.com/w/cpp/language/overload_resolution
https://stackoverflow.com/questions/29090692/how-is-ambiguity-determined-in-the-overload-resolution-algorithm
...] let ICSi(F) denote the implicit conversion sequence that converts the i-th argument in
 the list to the type of the i-th parameter of viable function F.
[...] a viable function F1 is defined to be a better function than another viable function F2
if for all arguments i, ICSi(F1) is not a worse conversion sequence than ICSi(F2), and then
— for some argument j, ICSj(F1) is a better conversion sequence than ICSj(F2)
*/
/*
bool isImplictlyConvertible(Type sourceType, Type targetType) {
  if (sourceType == targetType) return true;
  return sourceType.visit!(
    delegate (TupleType source) {
      return targetType.visit!(
        delegate (TupleType target) {
          if (source.elementTypes.length != target.elementTypes.length)
            return false;
          for (int i = 0; i < source.elementTypes.length; ++i) {
            if (!source.elementTypes[i].isImplictlyConvertible(target.elementTypes[i]))
              return false;
          }
          return true;
        },
        (Type type) => false
      );
    },
    (Type type) => false
  );
}*/
/*
for (int i = 0; i < type.parameterTypes.length; ++i) {
  Type paramType = type.parameterTypes[i];
  Type argType = expr.arguments[i].type;
  if (paramType != argType)
  {
    if (isModule(expr.arguments[i]))
    {
      expr.arguments[i] = new MemberExpr(expr.arguments[i], context.token(Identifier, "output"));
      accept(expr.arguments[i]);
      continue outer;
    }
    else
      error(expr.arguments[i], "Cannot implicity convert argument of type " ~ mangled(argType) ~ " to " ~ mangled(paramType));
  }
}
*/
