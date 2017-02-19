module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
public import duck.compiler.transforms;
public import duck.compiler.visitors.visit;
public import duck.compiler.visitors.source;
public import duck.compiler.visitors.codegen;
public import duck.compiler.visitors.dup;

import duck.compiler.dbg;
import duck.compiler.buffer;
import std.traits, std.conv, std.typetuple;


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
      accept(expr.callable);
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
