module duck.compiler.visitors.source;

import duck.compiler.visitors.visit;
import duck.compiler.buffer, duck.compiler.ast, duck.compiler.lexer;

Slice findSource(Node n) { return V().accept(n); }

private alias V = Visitor!(
  (ErrorExpr expr) => expr.slice,
  (TypeExpr expr) => expr.expr.findSource(),
  (ArrayLiteralExpr expr) {
    Slice s;
    foreach (i, arg ; expr.exprs) {
      s = s + arg.findSource();
    }
    return Slice();
  },
  (InlineDeclExpr expr) => expr.declStmt.findSource(),
  (RefExpr expr) => expr.identifier,
  (LiteralExpr expr) => expr.token.slice,
  (IdentifierExpr expr) => expr.token.slice,
  (BinaryExpr expr) => expr.left.findSource() + expr.operator + expr.right.findSource(),
  (UnaryExpr expr) => expr.operator + expr.operand.findSource(),
  (TupleExpr expr) {
    Slice s;
    foreach (ref Expr e; expr) {
      s = s + e.findSource();
    }
    return s;
  },
  (CallExpr expr) => expr.expr.findSource() + expr.arguments.findSource(),
  (IndexExpr expr) => expr.expr.findSource() + expr.arguments.findSource(),
  (ReturnStmt stmt) => stmt.expr.findSource(),
  (ExprStmt stmt) => stmt.expr.findSource(),
  (Stmts stmt) {
    Slice s;
    foreach (i, sm; stmt.stmts) {
      s = s + sm.findSource();
    }
    return s;
  },
  (VarDeclStmt s) {
    if (s.expr)
      return s.expr.findSource();
    return Slice();
  },
  (ImportStmt s) => s.identifier.slice,
  (TypeDeclStmt s) => Slice()
);
