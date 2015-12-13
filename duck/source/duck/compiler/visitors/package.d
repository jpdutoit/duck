module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
public import duck.compiler.transforms;

public import duck.compiler.visitors.codegen;

import duck.compiler.buffer;
import std.traits;

auto accept(N, Visitor)(N node, auto ref Visitor visitor) if (is(N : Node)){
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

R acceptNodes(R, N, Visitor)(N node, auto ref Visitor visitor) {
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

R acceptTypes(R, N, Visitor)(N node, auto ref Visitor visitor) {
  import duck.compiler.dbg;
  switch(node.kind) {
    foreach(Type; Types) {
      static if (is(Type : N) && is(typeof(visitor.visit(cast(Type)node))))
        case Type.Kind: return visitor.visit(cast(Type)node);
    }
    default:
      throw __ICE("Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
  }
}

import std.typetuple;

template visit(alias T) if (isSomeFunction!(T)) {
  import duck.compiler.dbg;
  auto visit(N)(N node) {
    pragma(inline, true);
    if (auto n = cast(ParameterTypeTuple!(T)[0])node)
      return T(n);
    else
      throw __ICE("Can not visit node of type " ~ node.classinfo.name);
    //return acceptR!(CommonType!(staticMap!(ReturnType, T)))(node, DelegateVisitor());
  }
}

template visit(T...) if (T.length > 1) {
  import std.conv;
  alias ReturnTypes = staticMap!(ReturnType, T);
  string genCode() {
    auto code = "struct DelegateVisitor {\n";
    foreach(i, t; T) {
      auto idx  = i.to!string;
      code ~= "  ReturnTypes["~ idx ~ "] visit(ParameterTypeTuple!(T["~idx~"])[0] n) { return T["~idx~"](n); }\n";
    }
    return code ~ "\n}";
  }
  auto visit(N)(N node) if (is(N : Node)) {
    mixin(genCode());
    return acceptNodes!(CommonType!(staticMap!(ReturnType, T)), N, DelegateVisitor)(node, DelegateVisitor());
  }
  auto visit(N)(N node) if (is(N : Type)) {
    mixin(genCode());
    return acceptTypes!(CommonType!(staticMap!(ReturnType, T)), N, DelegateVisitor)(node, DelegateVisitor());
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

    void recurse(TupleExpr expr) {
      foreach (ref e; expr) {
        accept(e);
      }
    }
    void recurse(CallExpr expr) {
      accept(expr.expr);
      accept(expr.arguments);
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
    (MemberExpr expr) => new MemberExpr(dupl(expr.left), expr.right),
    (IdentifierExpr expr) => expr
  );
}


struct Dup {
  Node visit(MemberExpr expr) {
    return new MemberExpr(dup(expr.left), expr.right);
  }

  Node visit(IdentifierExpr expr) {
    return expr.token ? new IdentifierExpr(expr.token) : new IdentifierExpr(expr.identifier);
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
  Slice visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    return expr.token.slice;
  }
  Slice visit(BinaryExpr expr) {
    return expr.left.accept(this) + expr.operator + expr.right.accept(this);
  }
  Slice visit(UnaryExpr expr) {
    return expr.operator + expr.operand.accept(this);
  }
  Slice visit(TupleExpr expr) {
    Slice s;
    foreach (ref Expr e; expr) {
      s = s + e.accept(this);
    }
    return s;
  }
  Slice visit(CallExpr expr) {
    return expr.expr.accept(this) + expr.arguments.accept(this);
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
  }
}
