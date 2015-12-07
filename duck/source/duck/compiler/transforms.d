module duck.compiler.transforms;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.buffer;
import duck.compiler.context;
import duck.compiler;
import duck.compiler.visitors;

struct Flatten {
  void accept(Node node) {
    node.accept(this);
  }

  void merge(ref Stmt[] all, Stmt stmt) {
    if (auto stmts = cast(Stmts)stmt) {
      foreach(s; stmts.stmts) {
        merge(all, s);
      }
    } else {
      all ~= stmt;
    }
  }
  void visit(Stmts stmts) {
    Stmt[] all;
    merge(all, stmts);
    stmts.stmts = all;
  }

  void visit(T)(T node) {
    recurse(node);
  }

  mixin DepthFirstRecurse;
}

auto flatten(Node node) {
  node.accept(Flatten());
  return node;
}
