module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
public import duck.compiler.visitors.visit;
public import duck.compiler.visitors.dup;

import duck.compiler.dbg: log, prettyName, logIndent, logOutdent;
import duck.compiler.buffer;
import std.traits, std.conv, std.typetuple;

auto traverseFind(alias T)(Node node)  if (isSomeFunction!(T)) {
  ReturnType!T found;
  Traverse v(ParameterTypeTuple!(T)[0] t) {
    if (auto f = T(t)) {
      found = f;
      return Traverse.abort;
    }
    return Traverse.proceed;
  }
  node.accept(Traverser!v());
  return found;
}

auto traverseCollect(alias T)(Node node) if (isSomeFunction!(T)) {
  ReturnType!T found[];
  Traverse v(ParameterTypeTuple!(T)[0] t) {
    if (auto f = T(t)) {
      found ~= f;
      return Traverse.skip;
    }
    return Traverse.proceed;
  }
  node.accept(Traverser!v());
  return found;
}

void traverse(T...)(Node node) {
  node.accept(Traverser!T());
}

enum Traverse {
  abort,
  skip,
  proceed,
};

struct Traverser(T...) {
  Visitor!T receiver;
  bool abort = false;

  void visit(T: Node)(T node) {
    if (abort) return;
    static if (is(typeof(receiver.visit(node)) R)) {
      static if (is(R : Traverse)) {
        auto result = receiver.visit(node);
        final switch (result) {
          case Traverse.abort: abort = true;
          case Traverse.skip: return;
          case Traverse.proceed: break;
        }
      } else
        receiver.visit(node);
    }
    recurse(node);
  }

  mixin RecursiveAccept;
}

mixin template RecursiveAccept() {
  void accept(Node node) {
    node.accept!void(this);
  }

  void recurse(Node node) {
    throw new Exception("Node type " ~ node.prettyName ~ " unhandled in ExprTraverse");
  }

  void recurse(CastExpr expr) {
    accept(expr.expr);
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
    if (expr.callable)
      accept(expr.callable);
    accept(expr.arguments);
  }

  void recurse(MemberExpr expr) {
    accept(expr.context);
  }

  void recurse(RefExpr expr) {
    if (expr.context)
      accept(expr.context);
  }

  void recurse(TypeExpr expr) {
    accept(expr.expr);
  }

  void recurse(IdentifierExpr) { }
  void recurse(LiteralExpr expr) { }

  void recurse(ArrayLiteralExpr expr) {
    foreach(e; expr.exprs)
      accept(e);
  }

  void recurse(IndexExpr expr) {
    accept(expr.expr);
    accept(expr.arguments);
  }

  void recurse(IfStmt stmt) {
    accept(stmt.condition);
    accept(stmt.trueBody);
    if (stmt.falseBody)
      accept(stmt.falseBody);
  }

  void recurse(BlockStmt block) {
    foreach(stmt; block)
      accept(stmt);
  }

  void recurse(ReturnStmt stmt) {
    accept(stmt.expr);
  }

  void recurse(ExprStmt stmt) {
    accept(stmt.expr);
  }

  void recurse(Decl decl) {}

  void recurse(Library library) {
    accept(library.stmts);
  }

  void recurse(DeclStmt stmt) {
    accept(stmt.decl);
  }

  void recurse(ImportStmt stmt) {
    accept(stmt.targetContext.library);
  }
}
