module duck.compiler.visitors.dup;

import duck.compiler.ast;
import duck.compiler.dbg;
import duck.compiler.visitors.visit;

T dup(T : Expr)(T t) {
  if (!t) return null;
  auto result = cast(T)t.clone;
  ASSERT(result, "Expected non-null duplicate of " ~ T.stringof);
  return result;
}

Expr dupWithReplacements()(Expr expr, Expr[Decl] replacements) {
  return expr.clone(replacements);
}

private Expr clone(Expr expr, Expr[Decl] replacements = (Expr[Decl]).init) {
  import std.array, std.algorithm.iteration;
  Expr cloneImpl(Expr expr) {
    if (!expr) return null;
    return expr.visit!(
      (MemberExpr expr) => new MemberExpr(cloneImpl(expr.context), expr.name, expr.source),
      (IdentifierExpr expr) => expr,
      (RefExpr expr) {
        auto replacement = expr.decl in replacements;
        return replacement
          ? *replacement
          : new RefExpr(expr.decl, cloneImpl(expr.context), expr.source);
      },
      (LiteralExpr expr) => expr,
      (ConstructExpr expr) => new ConstructExpr(cloneImpl(expr.callable), cast(TupleExpr)cloneImpl(expr.arguments), cloneImpl(expr.context), expr.source),
      (CallExpr expr) => new CallExpr(cloneImpl(expr.callable), cast(TupleExpr)cloneImpl(expr.arguments), cloneImpl(expr.context), expr.source),
      (BinaryExpr expr) => new BinaryExpr(expr.operator, cloneImpl(expr.left), cloneImpl(expr.right), expr.source),
      (TupleExpr expr) => new TupleExpr(expr.elements.map!(e => cloneImpl(e)).array)
    );
  }

  auto copy = cloneImpl(expr);
  copy.exprType = expr._exprType;
  return copy;
}
