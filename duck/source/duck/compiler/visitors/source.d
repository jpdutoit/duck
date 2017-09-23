module duck.compiler.visitors.source;

import duck.compiler.visitors.visit;
import duck.compiler.buffer, duck.compiler.ast, duck.compiler.lexer;

Slice findSource(Node n) { return V().accept(n); }

private alias V = Visitor!(
  (Expr expr) => expr.source,
  (ReturnStmt stmt) => stmt.expr.findSource(),
  (ExprStmt stmt) => stmt.expr.findSource(),
  (Stmts stmt) {
    Slice s;
    foreach (i, sm; stmt.stmts) {
      s = s + sm.findSource();
    }
    return s;
  },
  (DeclStmt stmt) {
    return stmt.decl.visit!(
      (VarDecl decl) {
        Slice s = decl.name;
        if (decl.valueExpr)
          s = s + decl.valueExpr.source;
        if (decl.typeExpr)
          s = s + decl.typeExpr.source;
        return s;
      },
      (Decl decl) => Slice()
    );
  },
  (IfStmt s) => s.condition.findSource(),
  (ImportStmt s) => s.identifier
);
