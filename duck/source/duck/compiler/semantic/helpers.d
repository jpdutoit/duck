module duck.compiler.semantic.helpers;

import duck.compiler.ast;
import duck.compiler.types;

bool hasError(Expr expr) {
  return expr._exprType is ErrorType;
}

bool hasType(Expr expr) {
  return expr._exprType !is null;
}

auto taint(Expr expr) {
  expr.exprType = ErrorType;
  return expr;
}

auto taint(Decl decl) {
  decl.declType = ErrorType;
  return decl;
}


bool isLValue(Expr expr) {
  if (!!cast(RefExpr)expr) return true;
  if (auto memberExpr = cast(MemberExpr)expr) {
    return isLValue(memberExpr.left);
  }
  return false;
}


bool isModule(Expr expr) {
  return expr.exprType.kind == ModuleType.Kind;
}
