module duck.compilers.visitors.tree_print;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
import duck.compilers.visitors.expr_to_string;

String className(Type type) {
  //return "";
  if (!type) return "τ";
  return "τ-"~mangled(type);
}

struct TreePrint {
  alias VisitResultType = Node;
  int depth = 0;
  enum string PAD = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";

  string padding() { return PAD[0..depth]; };

  auto accept(Node node) {
    return node.accept(this);
  }
  Node visit(InlineDeclExpr expr) {
    writefln("%s InlineDeclExpr", padding);
    depth++;
    expr.declStmt.accept(this);
    depth--;
    return expr;
  }

  Node visit(ArrayLiteralExpr expr) {
    String s = "[";
    foreach (i, e ; expr.exprs) {
      if (i != 0) s ~= ",";
      s ~= e.accept(ExprToString());
    }
    writefln("%s%s", padding, s);
    return expr;
  }
  Node visit(MemberExpr expr) {
    writefln("%s.%s - %s", padding, expr.identifier.value, mangled(expr._exprType));
    depth++;
    expr.expr.accept(this);
    depth--;
    return expr;
  }
  Node visit(LiteralExpr expr) {
    if (expr.token.type == StringLiteral)
      writefln("%s'%s' - %s", padding, expr.token.value[1..$-1], mangled(expr._exprType));
    else
      writefln("%s%s - %s", padding, expr.token.value, mangled(expr._exprType));
    return expr;
  }
  Node visit(IdentifierExpr expr) {
    writefln("%s'%s' - %s", padding, expr.token.value, mangled(expr._exprType));
    return expr;
  }

  Node visit(BinaryExpr expr) {
    writefln("%s%s - %s", padding, expr.operator.value, mangled(expr._exprType));
    depth++;
    expr.left.accept(this);
    expr.right.accept(this);
    depth--;
    return expr;
  }
  Node visit(PipeExpr expr) {
    writefln("%s%s - %s", padding, expr.operator.value, mangled(expr._exprType));
    depth++;
    expr.left.accept(this);
    expr.right.accept(this);
    depth--;
    return expr;
  }
  Node visit(AssignExpr expr) {
    writefln("%s%s - %s", padding, expr.operator.value, mangled(expr._exprType));
    depth++;
    expr.left.accept(this);
    expr.right.accept(this);
    depth--;
    return expr;
  }
  Node visit(UnaryExpr expr) {
    writefln("%s%s - %s", padding, expr.operator.value, mangled(expr._exprType));
    depth++;
    expr.operand.accept(this);
    depth--;
    return expr;
  }
  Node visit(CallExpr expr) {
    if (auto refExpr = cast(RefExpr)expr.expr) {
        auto s = refExpr.identifier.value;
        writefln("%sCall %s : %s - %s", padding, s, mangled(expr.expr._exprType), mangled(expr._exprType));
    } else {
      writefln("%sCall %s - %s", padding, mangled(expr.expr._exprType), mangled(expr._exprType));
      depth++;
      expr.expr.accept(this);
      depth--;
    }
    depth++;
    foreach (i, arg ; expr.arguments) {
      arg.accept(this);
    }
    depth--;
    return expr;
  }
  Node visit(Decl decl) {
    writefln("%sDecl %s", padding, decl.declType.mangled);
    return decl;
  }
  Node visit(DeclStmt stmt) {
    writefln("%sDeclStmt %s - %s", padding, stmt.identifier.value, mangled(stmt.expr._exprType));
    depth++;
    stmt.expr.accept(this);
    depth--;
    return stmt;
  }
  Node visit(RefExpr expr) {
    writefln("%sRefExpr %s - %s", padding, expr.identifier.value, mangled(expr._exprType));
    //depth++;
    //expr.decl.accept(this);
    //depth--;
    return expr;
  }
  /*Node visit(Expr expr) {
    writefln("%s Expr %s", padding, expr.accept(ExprToString()));
    //writefln("%s  %s", padding, );
    return expr;
  }*/
  Node visit(ExprStmt stmt) {
  //  writefln("%s ExprStmt %s", padding, stmt.expr.accept(ExprToString()));
    //depth++;
    stmt.expr.accept(this);
    //depth--;
    return stmt;
  }
  Node visit(Stmts expr) {
    writefln("%sStmts", padding);
    depth++;
    foreach (i, stmt; expr.stmts) {
      stmt.accept(this);
    }
    depth--;
    return expr;
  }
  Node visit(ScopeStmt expr) {
    writefln("%sScopeStmt", padding);
    depth++;
    expr.stmts.accept(this);
    depth--;
    return expr;
  }

  Node visit(Program mod) {
    writefln("%stree", padding);
    depth++;
    writefln("%sProgram", padding);
    depth++;
    writefln("%sDecls", padding);
    depth++;
    foreach (i, decl; mod.decls) {
      decl.accept(this);
    }
    depth--;
    writefln("%sStmts", padding);
    depth++;
    foreach (i, node; mod.nodes) {
      node.accept(this);
    }
    depth--;
    depth--;
    depth--;
    return mod;
  }
}
