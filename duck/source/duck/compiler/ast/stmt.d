module duck.compiler.ast.stmt;

import duck.util.list;
import duck.compiler;
import duck.compiler.lexer;

abstract class Stmt : Node {
  BlockStmt parent;
  Stmt prev;
  Stmt next;

  final void insertBefore(Stmt stmt) {
    stmt.parent.insertBefore(this, stmt);
  }

  final void insertAfter(Stmt stmt) {
    stmt.parent.insertAfter(stmt, this);
  }
}

class BlockStmt : Stmt {
  mixin NodeMixin;
  this() {
  }

  final void append(Decl decl) {
    this.append(new DeclStmt(decl).withSource(decl));
  }

  final void append(Stmt stmt) {
    list.append(stmt);
  }

  mixin List!Stmt list;
}

class DeclStmt: Stmt {
  mixin NodeMixin;
  Decl decl;

  this(Decl decl) {
    this.decl = decl;
    this.source = decl.source;
  }
}

class ScopeStmt : BlockStmt {
  mixin NodeMixin;
}

class ExprStmt : Stmt {
  mixin NodeMixin;

  Expr expr;
  this(Expr expr) {
    this.expr = expr;
  }
}

class ReturnStmt : Stmt {
  mixin NodeMixin;

  Expr value;
  this(Expr value) {
    this.value = value;
  }
}

class IfStmt: Stmt {
  mixin NodeMixin;

  Expr condition;
  Stmt trueBody, falseBody;

  this(Expr condition, Stmt trueBody, Stmt falseBody) {
    this.condition = condition;
    this.trueBody = trueBody;
    this.falseBody = falseBody;
  }
}

class WithStmt: Stmt {
  mixin NodeMixin;

  Expr valueExpr;
  Stmt withBody;

  this(Expr valueExpr, Stmt withBody) {
    this.valueExpr = valueExpr;
    this.withBody = withBody;
  }
}
