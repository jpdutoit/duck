module duck.compilers.visitors.expr_to_string;

import duck.compiler.ast, duck.compiler.token, duck.compiler.types;
import duck.compiler.transforms;

String className(Type type) {
	//return "";
	if (!type) return "τ";
	return "τ-"~mangled(type);
}

struct ExprToString {
	alias VisitResultType = String;

	String visit(ArrayLiteralExpr expr) {
		String s = "[";
		foreach (i, e ; expr.exprs) {
			if (i != 0) s ~= ",";
			s ~= e.accept(this);
		}
		return s ~ "]";
	}
	String visit(DeclExpr expr) {
		return className(expr._exprType) ~ "(" ~ expr.identifier.value ~ ") ";
	}
	String visit(MemberExpr expr) {
		return className(expr._exprType)~"(" ~ expr.expr.accept(this) ~ "." ~ expr.identifier.value ~ ") ";
	}
	String visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
		return className(expr._exprType) ~ "("  ~ expr.token.value ~ ") ";
	}
	String visit(BinaryExpr expr) {
		return className(expr._exprType)~"(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ") ";
	}
	String visit(PipeExpr expr) {
		return className(expr._exprType)~"(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ") ";
	}
	String visit(AssignExpr expr) {
		return className(expr._exprType)~"(" ~ expr.left.accept(this) ~ " " ~ expr.operator.value ~ " " ~ expr.right.accept(this) ~ ") ";
	}
	String visit(UnaryExpr expr) {
		return className(expr._exprType)~"(" ~ expr.operator.value ~ expr.operand.accept(this) ~ ") ";
	}
	String visit(CallExpr expr) {
		String s = className(expr._exprType) ~ "(" ~ expr.expr.accept(this) ~ "(";
		foreach (i, arg ; expr.arguments) {
			if (i != 0) s ~= ",";
			s ~= arg.accept(this);
		}
		return s ~ ")) ";
	}
}
