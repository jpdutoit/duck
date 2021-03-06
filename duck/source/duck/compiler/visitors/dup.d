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
  scope Expr cloneImpl(Expr expr) {
    if (!expr) return null;
    auto copy = expr.visit!(
      (MemberExpr expr) => new MemberExpr(cloneImpl(expr.context), expr.name, expr.source),
      (IdentifierExpr expr) => expr,
      (RefExpr expr) {
        auto replacement = expr.decl in replacements;
        if (replacement) {
          debug(Semantic) log("Replacing", expr.decl, "with", *replacement);
        }
        if (replacement)
          return *replacement;
        auto refExpr = new RefExpr(expr.decl, cloneImpl(expr.context), expr.source);
        foreach (decl, value; expr.contexts) {
          auto replacement = decl in replacements;
          if (replacement) {
            refExpr.contexts[decl] = *replacement;
            debug(Semantic) log("Replacing", decl, "with", *replacement);
          } else {
            refExpr.contexts[decl] = cloneImpl(value);
          }
        }
        return refExpr;
      },
      (CastExpr expr) => new CastExpr(cloneImpl(expr.expr), expr.targetType),
      (LiteralExpr expr) => expr,
      (ConstructExpr expr) => new ConstructExpr(cloneImpl(expr.callable), cast(TupleExpr)cloneImpl(expr.arguments), expr.source),
      (CallExpr expr) => new CallExpr(cloneImpl(expr.callable), cast(TupleExpr)cloneImpl(expr.arguments), expr.source),
      (BinaryExpr expr) => new BinaryExpr(expr.operator, cloneImpl(expr.left), cloneImpl(expr.right), expr.source),
      (TupleExpr expr) => new TupleExpr(expr.elements.map!(e => cloneImpl(e)).array),
    );
    copy.source = expr.source;
    copy.type = expr._type;
    return copy;
  }

  return cloneImpl(expr);
}
