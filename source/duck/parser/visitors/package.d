module duck.compiler.visitors;

import duck.compiler.ast, duck.compiler.token, duck.compiler.types;
public import duck.compiler.transforms;

public import duck.compilers.visitors.expr_to_string;
public import duck.compilers.visitors.expr_print;
public import duck.compilers.visitors.tree_print;
public import duck.compilers.visitors.codegen;

alias String = const(char)[];

String className(Type type) {
	//return "";
	if (!type) return "τ";
	return "τ-"~mangled(type);
}

struct LineNumber {
	alias VisitResultType = int;
	int visit(ArrayLiteralExpr expr) {
		foreach (i, arg ; expr.exprs) {
			int l = arg.accept(this);
			if (l) return l;
		}
		return 0;
	}
	int visit(DeclExpr expr) {
		return expr.identifier.lineNumber;
	}
	int visit(MemberExpr expr) {
		return expr.expr.accept(this) || expr.identifier.lineNumber();
	}
	int visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
		return expr.token.lineNumber();
	}
	int visit(BinaryExpr expr) {
		return expr.left.accept(this) || expr.operator.lineNumber() || expr.right.accept(this);
	}
	int visit(AssignExpr expr) {
		return expr.left.accept(this) || expr.operator.lineNumber() || expr.right.accept(this);
	}
	int visit(UnaryExpr expr) {
		return expr.operator.lineNumber() ||expr.operand.accept(this);
	}
	int visit(CallExpr expr) {
		int l = expr.expr.accept(this);
		if (l) return l;
		foreach (i, arg ; expr.arguments) {
			l = arg.accept(this);
			if (l) return l;
		}
		return 0;
	}
	int visit(Node node) {
		return 0;
	}
}
