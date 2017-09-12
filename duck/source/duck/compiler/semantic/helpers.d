module duck.compiler.semantic.helpers;

import duck.compiler.visitors;
import duck.compiler.context;

import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.lexer.tokens;

import duck.compiler.dbg;

import std.stdio;

T taint(T: Expr)(T expr) {
  expr.type = ErrorType.create;
  return expr;
}

D taint(D: ValueDecl)(D decl) {
  decl.type = ErrorType.create;
  return decl;
}

bool isCallable(Type type) {
  return type.visit!(
    (OverloadSetType o) => true,
    (FunctionType o) => true,
    (Type t) => false
  );
}

bool isCallable(Expr e) {
  return e.type.isCallable;
}

Expr findTarget(Expr expr) {
  return expr.visit!(
    (Expr expr) => cast(Expr)null,
    (RefExpr expr) => expr.context);
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
    (Expr e) => false
  );
}

bool isPipeTarget(Expr expr) {
  return expr.visit!(
    (IndexExpr i) => isPipeTarget(i.expr),
    (IdentifierExpr i) => true,
    (RefExpr r) => r.context && r.context.type.as!ModuleType && r.decl.as!FieldDecl,
    (Expr e) => false
  );
}

TypeDecl getTypeDecl(Expr expr) {
  return expr.visit!(
    (TypeExpr te) => te.decl,
    (RefExpr re) => cast(TypeDecl)re.decl,
    (Expr e) => null
  );
}

Type getResultType(Decl decl, int line = __LINE__, string file = __FILE__) {
  return decl.visit!(
    (OverloadSet os) {
      if (os.decls.length == 1)
        return os.decls[0].getResultType(line, file);
      return ErrorType.create();
    },
    (FieldDecl fd) => fd.type,
    (CallableDecl cd) => cd.type.returnType
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
