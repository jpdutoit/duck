module duck.compiler.dbg.conv;

import duck.compiler.dbg.colors;
import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.visitors;

string toString(Expr expr) {
  return expr.accept(ExprToString(true));
}

private:

struct ExprToString {
  bool showTypes;
  this(bool showTypes) {
    this.showTypes = showTypes;
  }

  string annotate(string whatever, Type type) {
    if (!showTypes) return whatever;
    if (!type) return "?".green();
    return "(" ~ whatever ~ ":" ~ type.describe.green() ~ ")";
  }

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
    auto name = expr.decl.name.value;
    if (!name) name = "_";
    return annotate((expr.context ? expr.context.toString() ~ "." : "") ~ name.blue, expr._type);
  }
  string visit(MemberExpr expr) {
    return annotate("(" ~ expr.context.accept(this) ~ "." ~ expr.name ~ ")", expr._type);
  }
  string visit(IdentifierExpr expr) {
    auto name = expr.identifier.value;
    if (!name) name = "_";
    return annotate(name.blue, expr._type);
  }
  string visit(LiteralExpr expr) {
    return annotate(expr.value.blue, expr._type);
  }
  string visit(CastExpr expr) {
    return annotate("(cast " ~ expr.expr.accept(this) ~ ")", expr.targetType);
  }
  string visit(BinaryExpr expr) {
    return annotate("(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")", expr._type);
  }
  string visit(PipeExpr expr) {
    return annotate("(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")", expr._type);
  }
  string visit(AssignExpr expr) {
    return annotate("(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ")", expr._type);
  }
  string visit(UnaryExpr expr) {
    return annotate("(" ~ expr.operator.value ~ expr.operand.accept(this) ~ ")", expr._type);
  }
  string visit(TupleExpr expr) {
    string s = "(";
    foreach (i, arg ; expr.elements) {
      if (i != 0) s ~= ", ";
      s ~= arg.accept(this);
    }
    return annotate(s ~ ")", expr._type);
  }
  string visit(ConstructExpr expr) {
    if (expr.callable) {
      return visit(cast(CallExpr)expr);
    }
    return annotate("alloc()", expr._type);
  }
  string visit(CallExpr expr) {
    string s = expr.callable.accept(ExprToString(false)) ~ "(";
    foreach (i, arg ; expr.arguments.elements) {
      if (i != 0) s ~= ", ";
      s ~= arg.accept(this);
    }
    return annotate(s ~ ")", expr._type);
  }
  string visit(IndexExpr expr) {
    string s = expr.expr.accept(this) ~ "[";
    foreach (i, arg ; expr.arguments.elements) {
      if (i != 0) s ~= ", ";
      s ~= arg.accept(this);
    }
    return annotate(s ~ "]", expr._type);
  }
}
