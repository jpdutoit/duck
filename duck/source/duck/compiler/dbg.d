module duck.compiler.dbg;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
public import std.exception : enforce;

auto __ICE(string message = "", int line = __LINE__, string file = __FILE__) {
  import core.exception;
  import std.conv;
  import std.stdio;
  auto msg = "Internal compiler error: " ~ message ~ " at " ~ file ~ "(" ~ line.to!string ~ ") ";
  stderr.writeln(msg);
  return new AssertError(msg);
}


string describe(const Type type) {
  return type ? type.mangled() : "?";
}

string annot(string whatever, Type type) {
  if (!type) return whatever;
  return whatever ~ " : " ~ type.describe();
}

mixin template TreeLogger() {
  enum string PAD = "                                                                                         ";
  static string logPadding(int __depth) { return PAD[0..__depth*4]; }
  int logDepth;
  void logIndent() { logDepth++; }
  void logOutdent() { logDepth--; }
  void log(T...)(string where, T t) {
    import std.stdio : write, writeln, stderr;
    stderr.write(logPadding(logDepth), where, "");
    foreach(tt; t) {
      stderr.write(" ", tt);
    }
    stderr.writeln();
  }
}

struct ExprToString {

  string visit(ArrayLiteralExpr expr) {
    string s = "[";
    foreach (i, e ; expr.exprs) {
      if (i != 0) s ~= ",";
      s ~= e.accept(this);
    }
    return s ~ "]";
  }
  string visit(RefExpr expr) {
    return "(" ~ expr.identifier.value.annot(expr._exprType) ~ ")";
  }
  string visit(MemberExpr expr) {
    return "(" ~ expr.expr.accept(this) ~ "." ~ expr.identifier.value.annot(expr._exprType) ~ ")";
  }
  string visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    return "("  ~ expr.token.value ~ "".annot(expr._exprType) ~ ")";
  }
  string visit(BinaryExpr expr) {
    return ("(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")").annot(expr._exprType);
  }
  string visit(PipeExpr expr) {
    return "(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")".annot(expr._exprType);
  }
  string visit(AssignExpr expr) {
    return "(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")".annot(expr._exprType);
  }
  string visit(UnaryExpr expr) {
    return "(" ~ expr.operator.value ~ expr.operand.accept(this) ~ ")".annot(expr._exprType);
  }
  string visit(CallExpr expr) {
    string s = "(" ~ expr.expr.accept(this) ~ "(";
    foreach (i, arg ; expr.arguments) {
      if (i != 0) s ~= ",";
      s ~= arg.accept(this);
    }
    return s ~ "))".annot(expr._exprType);
  }
}
