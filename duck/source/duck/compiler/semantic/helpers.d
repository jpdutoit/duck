module duck.compiler.semantic.helpers;

import duck.compiler.visitors;
import duck.compiler.context;

import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.lexer.tokens;

import duck.compiler.dbg;

import std.stdio;

struct ImportPaths
{
  string target;
  string sourcePath;
  string[] packageRoots;

  this(string _target, string _sourcePath, string[] _packageRoots) {
    target = _target;
    sourcePath = _sourcePath;
    packageRoots = _packageRoots;
  }

  int opApply(int delegate(size_t i, string path) dg)
  {
    import std.path : buildNormalizedPath;
    int result = 0;

    if (target[0] == '.' || target[0] == '/') {
      return dg(0, buildNormalizedPath(sourcePath, "..", target ~ ".duck"));
    }

    for (size_t i = 0; i < packageRoots.length; ++i) {
      result = dg(i, buildNormalizedPath(packageRoots[i], "duck_packages", target ~ ".duck"));
      if (result)
        break;
    }

    return result;
  }
}


bool hasError(Expr expr) {
  return (cast(ErrorType)expr._exprType) !is null;
}

bool hasType(Expr expr) {
  return expr._exprType !is null;
}

auto taint(Expr expr) {
  expr.exprType = ErrorType.create;
  return expr;
}

auto taint(Decl decl) {
  decl.declType = ErrorType.create;
  return decl;
}

Expr findTarget(Expr expr) {
  return expr.visit!(
    (Expr expr) => cast(Expr)null,
    (MemberExpr expr) => expr.left);
}

bool isLValue(Expr expr) {
  return expr.visit!(
    (IndexExpr i) => isLValue(i.expr),
    (IdentifierExpr i) => true,
    (RefExpr r) => true,
    (MemberExpr m) => isLValue(m.left),
    (Expr e) => false
  );
}


Decl getTypeDecl(Expr expr) {
  return expr.visit!(
    (TypeExpr te) => te.decl,
    (RefExpr re) => re.decl,
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
    (FieldDecl fd) => fd.declType,
    (CallableDecl cd) {
      auto ft = cast(FunctionType)cd.declType;
      return ft.returnType;
    }
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
  Type argType = expr.arguments[i].exprType;
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


bool isModule(Expr expr) {
  return expr.exprType.isKindOf!ModuleType;
}
