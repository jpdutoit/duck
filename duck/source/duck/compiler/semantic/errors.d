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

Stmt error(Stmt stmt, lazy string message) {
  context.error(stmt.source, message);
  return stmt;
}

void error(Slice token, string message) {
  context.error(token, message);
}

Expr errorResolvingConstructorCall(ConstructExpr expr, RefExpr ctors, CallableDecl[] viable) {
  if (!ctors) {
   return expr.error("No constructors found for type");
 }
 CallableDecl[] candidates;
 auto ot = ctors.type.enforce!OverloadSetType;
 if (viable.length == 0) {
   expr.error("None of these constructors matches arguments:");
   candidates = ot.overloadSet.decls;
 }
 else {
   error(expr, "Found multiple constructors matchin arguments:");
   candidates = viable;
 }
 foreach(CallableDecl callable; candidates) {
   if (callable.headerSource)
    info(callable.headerSource, "  " ~ callable.headerSource);
 }
 return expr.taint;
}
