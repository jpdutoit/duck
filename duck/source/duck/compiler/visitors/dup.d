module duck.compiler.visitors.dup;

import duck.compiler.ast;
import duck.compiler.dbg;
import duck.compiler.visitors.visit;

T dup(T : Expr)(T t) {
  auto result = cast(T)t.dupImpl;
  ASSERT(result, "Expected non-null duplicate of " ~ T.stringof);
  return result;
}

private Expr dupImpl(Expr expr) {
  import std.array, std.algorithm.iteration;
  return expr.visit!(
    (MemberExpr expr) => new MemberExpr(expr.left.dup, expr.right),
    (IdentifierExpr expr) => expr,
    (RefExpr expr) => expr,
    (LiteralExpr expr) => expr,
    (CallExpr expr) => new CallExpr(expr.dup, expr.arguments.dup, expr.context.dup),
    (BinaryExpr expr) => new BinaryExpr(expr.operator, expr.left.dup, expr.right.dup),
    (TupleExpr expr) => new TupleExpr(expr.elements.map!(e => e.dup).array)
  );
}
