module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
public import duck.compiler.transforms;

debug public import duck.compilers.visitors.expr_to_string;
debug public import duck.compilers.visitors.expr_print;
debug public import duck.compilers.visitors.tree_print;
public import duck.compilers.visitors.codegen;

alias String = const(char)[];

String className(Type type) {
  //return "";
  if (!type) return "τ";
  return "τ-"~mangled(type);
}

auto or(T...)(T t) {
  Span a = t[0];
  for (int i = 1; i < t.length; ++i) {
    a = a + t[i];
  }
}

T dup(T)(T t) {
  auto e = t.accept(Dup());
  return cast(T)e;
}


mixin template DepthFirstRecurse() {
    void recurse(BinaryExpr expr) {
      accept(expr.left);
      accept(expr.right);
    }

    void recurse(PipeExpr expr) {
      accept(expr.left);
      accept(expr.right);
    }

    void recurse(AssignExpr expr) {
      accept(expr.left);
      accept(expr.right);
    }

    void recurse(UnaryExpr expr) {
      accept(expr.operand);
    }

    void recurse(CallExpr expr) {
      foreach (i, ref arg ; expr.arguments) {
        accept(arg);
      }
      accept(expr.expr);
    }

    void recurse(MemberExpr expr) {
      accept(expr.expr);
    }

    void recurse(RefExpr expr) {
      accept(expr.decl);
    }

    void recurse(TypeExpr expr) {
      accept(expr.expr);
    }

    void recurse(Node node) {
    }
}

struct Dup {
  alias VisitResultType = Node;

  Node visit(MemberExpr expr) {
    return new MemberExpr(dup(expr.expr), expr.identifier);
  }

  Node visit(IdentifierExpr expr) {
    return new IdentifierExpr(expr.token);
  }
}


struct LineNumber {
  alias VisitResultType = Span;
  Span visit(TypeExpr expr) {
    return expr.expr.accept(this);
  }
  Span visit(ArrayLiteralExpr expr) {
    Span s;
    foreach (i, arg ; expr.exprs) {
      s = s + arg.accept(this);
    }
    return Span();
  }
  Span visit(InlineDeclExpr expr) {
    return expr.declStmt.accept(this);
  }
  Span visit(RefExpr expr) {
    return expr.identifier.span;
  }
  Span visit(MemberExpr expr) {
    return expr.expr.accept(this) + expr.identifier.span();
  }
  Span visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    return expr.token.span();
  }
  Span visit(PipeExpr expr) {
    return expr.left.accept(this) + expr.operator.span() +expr.right.accept(this);
  }
  Span visit(BinaryExpr expr) {
    return expr.left.accept(this) + expr.operator.span() + expr.right.accept(this);
  }
  Span visit(AssignExpr expr) {
    return expr.left.accept(this) + expr.operator.span() + expr.right.accept(this);
  }
  Span visit(UnaryExpr expr) {
    return expr.operator.span() + expr.operand.accept(this);
  }
  Span visit(CallExpr expr) {
    Span s = expr.expr.accept(this);
    foreach (i, arg ; expr.arguments) {
      s = s + arg.accept(this);
    }
    return s;
  }
  Span visit(ExprStmt stmt) {
    return stmt.expr.accept(this);
  }
  Span visit(Stmts stmt) {
    Span s;
    foreach (i, sm; stmt.stmts) {
      s = s + sm.accept(this);
    }
    return s;
  }
  Span visit(DeclStmt s) {
    return s.expr.accept(this);
  }
  /*int visit(Node node) {
    return 0;
  }*/
}
