module duck.compiler.dbg;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
import duck.compiler.visitors;
public import std.exception : enforce;

auto __ICE(string message = "", int line = __LINE__, string file = __FILE__) {
  import core.exception;
  import std.conv;
  import std.stdio;
  auto msg = "Internal compiler error: " ~ message ~ " at " ~ file ~ "(" ~ line.to!string ~ ") ";
  stderr.writeln(msg);
  asm {hlt;}
  return new AssertError(msg);
}


string describe(const Type type) {
  return type ? type.mangled() : "?";
}

string annot(string whatever, Type type) {
  if (!type) return whatever;
  return whatever ~ " : " ~ type.describe();
}

struct TreeLogger {
  enum string PAD = "                                                                                                                                           ";
  int logDepth;
  static string logPadding(int __depth) { return PAD[0..__depth*4]; }
  void _log(string what) {
    import std.stdio : write, writeln, stderr;
    stderr.write(logPadding(logDepth), what);
  }
}

__gshared TreeLogger _logger;
void logIndent() { _logger.logDepth++; }
void logOutdent() { _logger.logDepth--; }
void log(T...)(string what, T t) {
  import std.stdio : write, writeln, stderr;
  _logger._log(what);
  foreach(tt; t) stderr.write(" ", tt);
  stderr.writeln();
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
  string visit(TypeExpr expr) {
    return expr.expr.accept(this);
  }
  string visit(RefExpr expr) {
    return "(" ~ expr.decl.declType.describe.annot(expr._exprType) ~ ")";
  }
  string visit(MemberExpr expr) {
    return "(" ~ expr.left.accept(this) ~ "." ~ expr.right.accept(this).annot(expr._exprType) ~ ")";
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
  string visit(TupleExpr expr) {
    string s = "(";
    foreach (i, arg ; expr.elements) {
      if (i != 0) s ~= ",";
      s ~= arg.accept(this);
    }
    return s ~ ")".annot(expr._exprType);
  }
  string visit(CallExpr expr) {
    string s = "(call " ~ expr.expr.accept(this) ~ " " ~ expr.arguments.accept(this);
    return s ~ ")".annot(expr._exprType);
  }
  string visit(IndexExpr expr) {
    string s = "(index " ~ expr.expr.accept(this) ~ " " ~ expr.arguments.accept(this);
    return s ~ ")".annot(expr._exprType);
  }
}
