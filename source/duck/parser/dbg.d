module duck.compiler.dbg;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;

string describe(const Type type) {
  return type ? type.mangled() : "?";
}

String annot(String whatever, Type type) {
  if (!type) return whatever;
  return whatever ~ " : " ~ type.describe();
}
/*
String className(Type type) {
  if (!type)
    return "? : ";
  return mangled(type) ~ " : ";
}*/

struct ExprToString {

  String visit(ArrayLiteralExpr expr) {
    String s = "[";
    foreach (i, e ; expr.exprs) {
      if (i != 0) s ~= ",";
      s ~= e.accept(this);
    }
    return s ~ "]";
  }
  String visit(RefExpr expr) {
    return "(" ~ expr.identifier.value.annot(expr._exprType) ~ ")";
  }
  String visit(MemberExpr expr) {
    return "(" ~ expr.expr.accept(this) ~ "." ~ expr.identifier.value.annot(expr._exprType) ~ ")";
  }
  String visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    return "("  ~ expr.token.value ~ "".annot(expr._exprType) ~ ")";
  }
  String visit(BinaryExpr expr) {
    return ("(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")").annot(expr._exprType);
  }
  String visit(PipeExpr expr) {
    return "(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")".annot(expr._exprType);
  }
  String visit(AssignExpr expr) {
    return "(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")".annot(expr._exprType);
  }
  String visit(UnaryExpr expr) {
    return "(" ~ expr.operator.value ~ expr.operand.accept(this) ~ ")".annot(expr._exprType);
  }
  String visit(CallExpr expr) {
    String s = "(" ~ expr.expr.accept(this) ~ "(";
    foreach (i, arg ; expr.arguments) {
      if (i != 0) s ~= ",";
      s ~= arg.accept(this);
    }
    return s ~ "))".annot(expr._exprType);
  }
}
