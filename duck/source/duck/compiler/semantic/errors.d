module duck.compiler.semantic.errors;

import duck.compiler;
import duck.compiler.semantic.helpers;
import std.algorithm;

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

Expr error(R)(Expr expr, lazy string message, R decls)
  if (isDeclRange!R)
{
  if (expr.hasError) return expr;
  context.error(expr.source, message);
  info(decls);
  return expr.taint;
}

Stmt error(Stmt stmt, lazy string message) {
  context.error(stmt.source, message);
  return stmt;
}

void error(Slice token, string message) {
  context.error(token, message);
}

string typeClassDescription(T: MetaType)() { return "type"; }

void info(R)(R decls)
  if (isDeclRange!R)
{
  foreach(Decl decl; decls) {
    if (auto callable = decl.as!CallableDecl) {
      if (callable.headerSource)
        info(callable.headerSource, "  " ~ callable.headerSource);
    }
    else {
      info(decl.source, "  " ~ decl.source);
    }
  }
}

import std.range.primitives;


Expr errorResolvingCall(R)(CallExpr expr, R lookup, CallableDecl[] viable)
  if (isDeclRange!R)
{
  if (viable.length == 0)
    expr.error("No function matches arguments:", lookup);
  else
    error(expr, "Multiple functions matches arguments:", viable);
  return expr.taint;
}

Expr errorResolvingConstructorCall(R)(ConstructExpr expr, R ctors, CallableDecl[] viable)
  if (isDeclRange!R)
{
  if (ctors.empty) {
   return expr.error("No constructors found for type");
  }

  if (viable.length == 0) {
    expr.error("None of these constructors matches arguments:", ctors);
  }
  else {
    error(expr, "Found multiple constructors matching arguments:", viable);
  }
  return expr.taint;
}
