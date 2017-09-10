module duck.compiler.dbg.conv;

import duck.compiler.dbg.colors;
import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.visitors;

string toString(Expr expr) {
  return expr.accept(ExprToString());
}

private:

string annot(string whatever, Type type) {
  if (!type) return whatever;
  return whatever ~ ":" ~ type.describe().green;
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
  string visit(ErrorExpr expr) {
    return "ERROR";
  }
  string visit(TypeExpr expr) {
    return expr.expr.accept(this);
  }
  string visit(RefExpr expr) {
    auto source = expr.source.value;
    return "Ref".blue ~ "(" ~ (expr.context ? expr.context.toString() ~ "." : "") ~ expr.source.annot(expr._type) ~ ")";
  }
  string visit(MemberExpr expr) {
    return "(" ~ expr.context.accept(this) ~ "." ~ expr.name ~ ")".annot(expr._type);
  }
  string visit(IdentifierExpr expr) {
    return ""  ~ expr.identifier.blue ~ "".annot(expr._type) ~ "";
  }
  string visit(LiteralExpr expr) {
    return ""  ~ expr.value.blue ~ "".annot(expr._type) ~ "";
  }
  string visit(CastExpr expr) {
    return ("(cast " ~ expr.expr.accept(this).annot(expr.expr._type) ~ ")").annot(expr.targetType);
  }
  string visit(BinaryExpr expr) {
    return ("(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")").annot(expr._type);
  }
  string visit(PipeExpr expr) {
    return "(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")".annot(expr._type);
  }
  string visit(AssignExpr expr) {
    return "(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")".annot(expr._type);
  }
  string visit(UnaryExpr expr) {
    return "(" ~ expr.operator.value ~ expr.operand.accept(this) ~ ")".annot(expr._type);
  }
  string visit(TupleExpr expr) {
    string s = "(";
    foreach (i, arg ; expr.elements) {
      if (i != 0) s ~= ", ";
      s ~= arg.accept(this);
    }
    return s ~ ")".annot(expr._type);
  }
  string visit(ConstructExpr expr) {
    if (expr.callable) {
      return "construct:" ~ visit(cast(CallExpr)expr);
    }
    return "construct:(defaultCtor)";
  }
  string visit(CallExpr expr) {
    string s = "(" ~ expr.callable.accept(this) ~ "(";
    foreach (i, arg ; expr.arguments.elements) {
      if (i != 0) s ~= ", ";
      s ~= arg.accept(this);
    }
    return s ~ "))".annot(expr._type);
  }
  string visit(IndexExpr expr) {
    string s = "(" ~ expr.expr.accept(this) ~ "[";
    foreach (i, arg ; expr.arguments.elements) {
      if (i != 0) s ~= ", ";
      s ~= arg.accept(this);
    }
    return s ~ "])".annot(expr._type);
  }
}
