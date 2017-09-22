module duck.compiler.semantic.errors;

import duck.compiler;
import duck.compiler.ast;
import duck.compiler.types;

T taint(T: Expr)(T expr) {
  expr.type = ErrorType.create;
  return expr;
}

D taint(D: ValueDecl)(D decl) {
  decl.type = ErrorType.create;
  return decl;
}

void info(Slice slice, lazy string message) {
  context.info(slice, message);
}

Expr error(Expr expr, lazy string message) {
  if (expr.hasError) return expr;
  context.error(expr.source, message);
  return expr.taint;
}

void error(Slice token, string message) {
  context.error(token, message);
}
