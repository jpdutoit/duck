module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
public import duck.compiler.transforms;

public import duck.compiler.visitors.codegen;

import duck.compiler.buffer;
import std.traits;

auto accept(N, Visitor)(N node, auto ref Visitor visitor) {
  import duck.compiler.dbg;
  switch(node.nodeType) {
    foreach(NodeType; NodeTypes) {
      static if (is(NodeType : N) && is(typeof(visitor.visit(cast(NodeType)node))))
        case NodeType._nodeTypeId: return visitor.visit(cast(NodeType)node);
    }
    default:
      throw __ICE("Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
  }
}

R acceptR(R, N, Visitor)(N node, auto ref Visitor visitor) {
  import duck.compiler.dbg;
  switch(node.nodeType) {
    foreach(NodeType; NodeTypes) {
      static if (is(NodeType : N) && is(typeof(visitor.visit(cast(NodeType)node))))
        case NodeType._nodeTypeId: return visitor.visit(cast(NodeType)node);
    }
    default:
      throw __ICE("Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
  }
}

import std.typetuple;

template visit(T...) if (T.length > 1) {
  import std.conv;
  string genCode() {
    auto code = "struct DelegateVisitor {\n";
    foreach(i, t; T) {
      auto idx  = i.to!string;
      code ~= "  ReturnType!(T["~ idx ~ "]) visit(ParameterTypeTuple!(T["~idx~"])[0] n) { return T["~idx~"](n); }\n";
    }
    return code ~ "\n}";
  }
  auto visit(N)(N node) {
    mixin(genCode());
    return acceptR!(CommonType!(staticMap!(ReturnType, T)))(node, DelegateVisitor());
  }
}

void traverse(T)(Node node, bool delegate(T) dg) {
  struct TraverseVisitor {
    bool stopped = false;
    void visit(T t) {
      if (!stopped) {
        if (dg(t))
          recurse(t);
        else stopped = true;
      }
    }
    void visit(T)(T node) {
      if (!stopped) recurse(node);
    }
    mixin RecursiveAccept;
  }
  return node.accept(TraverseVisitor());
}


string className(Type type) {
  //return "";
  if (!type) return "τ";
  return "τ-"~mangled(type);
}

mixin template RecursiveAccept() {
    void accept(Node node) {
      node.accept(this);
    }

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
      accept(expr.left);
    }

    void recurse(RefExpr expr) {
      accept(expr.decl);
    }

    void recurse(TypeExpr expr) {
      accept(expr.expr);
    }

    void recurse(ImportStmt stmt) {
    }

    void recurse(ScopeStmt stmt) {
      accept(stmt.stmts);
    }
    void recurse(ExprStmt stmt) {
      accept(stmt.expr);
    }
    void recurse(Library library) {
      foreach (ref node ; library.nodes) {
        accept(node);
      }
    }
    void recurse(Node node) {

    }
}

T dup(T)(T t) {
  auto e = t.accept(Dup());
  return cast(T)e;
}

Expr dupl(Expr expr) {
  return expr.visit!(
    (MemberExpr expr) => new MemberExpr(dupl(expr.left), expr.identifier),
    (IdentifierExpr expr) => expr
  );
}


struct Dup {
  Node visit(MemberExpr expr) {
    return new MemberExpr(dup(expr.left), expr.identifier);
  }

  Node visit(IdentifierExpr expr) {
    return new IdentifierExpr(expr.token);
  }
}

struct LineNumber {
  Slice visit(ErrorExpr expr) {
      return expr.slice;
  }
  Slice visit(TypeExpr expr) {
    return expr.expr.accept(this);
  }
  Slice visit(ArrayLiteralExpr expr) {
    Slice s;
    foreach (i, arg ; expr.exprs) {
      s = s + arg.accept(this);
    }
    return Slice();
  }
  Slice visit(InlineDeclExpr expr) {
    return expr.declStmt.accept(this);
  }
  Slice visit(RefExpr expr) {
    return expr.identifier;
  }
  Slice visit(MemberExpr expr) {
    return expr.left.accept(this) + expr.identifier;
  }
  Slice visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    return expr.token.slice;
  }
  Slice visit(BinaryExpr expr) {
    return expr.left.accept(this) + expr.operator + expr.right.accept(this);
  }
  Slice visit(UnaryExpr expr) {
    return expr.operator + expr.operand.accept(this);
  }
  Slice visit(CallExpr expr) {
    Slice s = expr.expr.accept(this);
    foreach (i, arg ; expr.arguments) {
      s = s + arg.accept(this);
    }
    return s;
  }
  Slice visit(ExprStmt stmt) {
    return stmt.expr.accept(this);
  }
  Slice visit(Stmts stmt) {
    Slice s;
    foreach (i, sm; stmt.stmts) {
      s = s + sm.accept(this);
    }
    return s;
  }
  Slice visit(VarDeclStmt s) {
    return s.expr.accept(this);
  }
  Slice visit(ImportStmt s) {
    return Slice();
  }
  Slice visit(TypeDeclStmt s) {
    return Slice();
    //return s.decl.accept(this);
  }
  /*int visit(Node node) {
    return 0;
  }*/
}
