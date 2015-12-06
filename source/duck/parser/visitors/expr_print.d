module duck.compilers.visitors.expr_print;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
import duck.compilers.visitors.expr_to_string;

struct ExprPrint {
  alias VisitResultType = Node;
  int depth = 0;
  enum string PAD = "                                                                              ";

  string padding() { return PAD[0..depth*2]; };

  auto accept(Node node) {
    return node.accept(this);
  }
  /*Node visit(InlineDeclExpr expr) {
    writefln("%s DeclExpr %s", padding, expr.token.value);
    depth++;
    expr.decl.accept(this);
    depth--;
    return expr;
  }*/

  /*
  Node visit(MemberExpr expr) {
    writefln("%s MemberExpr %s", padding, expr.identifier.value);
    depth++;
    expr.expr.accept(this);
    depth--;
    return expr;
  }
  Node visit(LiteralExpr expr) {
    writefln("%s LiteralExpr %s", padding, expr.token.value);
    return expr;
  }
  Node visit(IdentifierExpr expr) {
    writefln("%s IdentifierExpr %s", padding, expr.token.value);
    return expr;
  }

  Node visit(BinaryExpr expr) {
    writefln("%s BinaryExpr %s", padding, expr.operator.value);
    depth++;
    expr.left.accept(this);
    expr.right.accept(this);
    depth--;
    return expr;
  }
  Node visit(UnaryExpr expr) {
    writefln("%s UnaryExpr %s", padding, expr.operator.value);
    depth++;
    expr.operand.accept(this);
    depth--;
    return expr;
  }
  Node visit(CallExpr expr) {
    writefln("%s CallExpr", padding);
    depth++;
    expr.expr.accept(this);
    foreach (i, arg ; expr.arguments) {
      arg.accept(this);
    }
    depth--;
    return expr;
  }*/
  Node visit(Decl decl) {
    writefln("%s Decl %s", padding, decl.declType.mangled);
    return decl;
  }
  Node visit(DeclStmt stmt) {
    writefln("%s DeclStmt %s", padding, stmt.identifier.value);
    depth++;
    stmt.expr.accept(this);
    depth--;
    return stmt;
  }
  Node visit(Expr expr) {
    writefln("%s Expr %s", padding, expr.accept(ExprToString()));
    //writefln("%s  %s", padding, );
    return expr;
  }
  Node visit(ExprStmt stmt) {
    writefln("%s ExprStmt %s", padding, stmt.expr.accept(ExprToString()));
    //depth++;
    //stmt.expr.accept(this);
    //depth--;
    return stmt;
  }
  Node visit(Stmts expr) {
    writefln("%s Stmts", padding);
    depth++;
    foreach (i, stmt; expr.stmts) {
      stmt.accept(this);
    }
    depth--;
    return expr;
  }
  Node visit(ScopeStmt expr) {
    writefln("%s ScopeStmt", padding);
    depth++;
    expr.stmts.accept(this);
    depth--;
    return expr;
  }

  Node visit(Program mod) {
    writefln("%s Program", padding);
    depth++;
    foreach (i, decl; mod.decls) {
      decl.accept(this);
    }
    foreach (i, node; mod.nodes) {
      node.accept(this);
    }
    depth--;
    return mod;
  }
}
