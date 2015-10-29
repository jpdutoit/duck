module duck.compiler.ast;

import duck.compiler.token, duck.compiler.types;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;
private import std.typecons: Rebindable;
alias NodeTypes = AliasSeq!(
	Program,
	Decl,
	VarDecl,
	TypeDecl,
	ConstDecl,
	FieldDecl,
	StructDecl,
	VarExpr,
	TypeExpr,
	ExprStmt,
	DeclStmt,
	ScopeStmt,
	ImportStmt,
	Stmts,
	DeclExpr,
	InlineDeclExpr,
	ArrayLiteralExpr,
	LiteralExpr,
	IdentifierExpr,
	UnaryExpr,
	AssignExpr,
	BinaryExpr,
	PipeExpr,
	MemberExpr,
	CallExpr);

mixin template NodeMixin() {
	static enum _nodeTypeId = staticIndexOf!(typeof(this), NodeTypes);
	static if (_nodeTypeId < 0) {
		//#TODO:0 Do it right
		static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in NodeTypes list.");
	}
	override NodeType nodeType() { return _nodeTypeId; };
};

abstract class Node {
	alias NodeType = ubyte;
	this() {
		//writefln("%s %s", this, &this);
	}
	NodeType nodeType();
};

abstract class Stmt : Node {
};

class Program : Node {
	mixin NodeMixin;

	Node[] nodes;
	Decl[] decls;

	this(Node[] nodes, Decl decls[]) {
		this.nodes = nodes;
		this.decls = decls;
	}
}

abstract class Decl : Node {
	mixin NodeMixin;

	Token name;
	//Expr expr;
	//Rebindable!(immutable Type) varType;
	//Token identifier;
  Type declType;

	this(Type type, Token name) {
		this.name = name;
		this.declType = type;
	}

/*	this(Token identifier, Expr expr, immutable .Type type = null) {
		this.varType = type;
		this.expr = expr;
		this.identifier = identifier;
	}*/
}

class FieldDecl : Decl{
	mixin NodeMixin;

	Expr typeExpr;
	alias identifier = name;

	this(Type type, Token identifier) {
		super(type, identifier);
	}

	this(Expr typeExpr, Token identifier) {
		super(null, identifier);
		this.typeExpr = typeExpr;
	}
}

class StructDecl : TypeDecl {
	mixin NodeMixin;

	Token identifier;
	FieldDecl[] fields;

	this(Type type, Token name, FieldDecl[] fields = null) {
		super(type, name);
		//this.identifier = identifier;
		this.fields = fields;
	}
}

/*class FuncDecl : Decl {
	Token identifier;
	Type returnType;
	FieldDecl[] arguments;
	this(Type type, Token identifier, Type returnType, FieldDecl[] args, Stmt funcBody) {
		super(type);
		this.identifier = identifier;
		this.returnType = type;
		this.arguments = args;
		this.fields = fields;
	}
}*/


// hz(number) => frequency
// frequency / frequency => number
// frequency + frequency => frequency
// frequency - frequency => frequency
// number * frequency => frequency

class VarDecl : Decl {
	mixin NodeMixin;

	Expr typeExpr;

	this(Type type, Token name) {
		super(type, name);
	}
	this(Expr typeExpr, Token identifier) {
		super(null, identifier);
		this.typeExpr = typeExpr;
	}
}

class TypeDecl : Decl {
	mixin NodeMixin;

	this(Type type, Token name) {
		super(type, name);
	}
}

class ConstDecl : Decl {
	mixin NodeMixin;
	Expr value;

	this(Type type, Token name, Expr value) {
		super(type, name);
		this.value = value;
	}
}

class Stmts : Stmt {
	mixin NodeMixin;
	Stmt[] stmts;

	this (Stmt[] stmts) {
		this.stmts = stmts;
	}
};

class ImportStmt : Stmt {
	mixin NodeMixin;
	Token identifier;

	this(Token identifier) {
		this.identifier = identifier;
	}
}

class DeclStmt : Stmt {
	mixin NodeMixin;

	Token identifier;
	Decl decl;
	Expr expr;

	this(Token token, Decl decl, Expr expr) {
		this.identifier = token;
		this.decl = decl;
		this.expr = expr;
	}
}

class ScopeStmt : Stmt {
	mixin NodeMixin;

	Stmts stmts;
	this(Stmts stmts) {
		this.stmts = stmts;
	}
}

abstract class Expr : Node {
	Type _exprType;

	@property bool exprTypeSet() {
		return _exprType !is null;
	}

	@property Type exprType() {
		if (!_exprType) {
			throw new Error("Trying to use expression type before it is calculated");
		}
		return _exprType;
	}

	@property void exprType(Type type) {
		_exprType = type;
	}

}
class ExprStmt : Stmt {
	mixin NodeMixin;

	Expr expr;
	this(Expr expr) {
		this.expr = expr;
	}
}

class InlineDeclExpr : IdentifierExpr {
	mixin NodeMixin;

	DeclStmt declStmt;

	this(Token token, DeclStmt declStmt) {
		super(token);
		this.declStmt = declStmt;
	}
}

class DeclExpr : Expr {
	mixin NodeMixin;

	Decl decl;
	Token identifier;

	this(Token identifier, Decl decl) {
		this.identifier = identifier;
		this.decl = decl;
	}
}

class VarExpr : Expr {
	mixin NodeMixin;

	VarDecl decl;
	this(VarDecl decl) {
		this.decl = decl;
	}
}

class TypeExpr : Expr {
	mixin NodeMixin;

	TypeDecl decl;
	this(TypeDecl decl) {
		this.decl = decl;
	}
}

class LiteralExpr : Expr {
	mixin NodeMixin;

	Token token;
	this(Token token) {
		this.token = token;
		if (token.type == Number)
			this.exprType = numberType;
		else if (token.type == StringLiteral)
			this.exprType = stringType;
	}
}

class ArrayLiteralExpr : Expr {
	mixin NodeMixin;

	Expr[] exprs;
	this(Expr[] exprs) {
		this.exprs = exprs;
	}
}

class IdentifierExpr : Expr {
	mixin NodeMixin;

	Token token;

	this(Token token) {
		this.token = token;
	}
}

class UnaryExpr : Expr {
	mixin NodeMixin;

	Token operator;
	Expr operand;

	this(Token op, Expr operand) {
		operator = op;
		this.operand = operand;
	}
}

class BinaryExpr : Expr {
	mixin NodeMixin;

	Token operator;
	Expr left, right;

	this(Token op, Expr left, Expr right) {
		this.operator = op;
		this.left = left;
		this.right = right;
	}
}

class PipeExpr : Expr {
	mixin NodeMixin;

	Token operator;
	Expr left, right;

	this(Token op, Expr left, Expr right) {
		this.operator = op;
		this.left = left;
		this.right = right;
	}
}


class AssignExpr : Expr {
	mixin NodeMixin;

	Token operator;
	Expr left, right;

	this(Token op, Expr left, Expr right) {
		this.operator = op;
		this.left = left;
		this.right = right;
	}
}

class MemberExpr : Expr {
	mixin NodeMixin;

	Expr expr;
	Token identifier;

	this(Expr expr, Token identifier) {
		this.expr = expr;
		this.identifier = identifier;
	}
}

class CallExpr : Expr {
	mixin NodeMixin;

	Expr expr;
	Expr[] arguments;

	this(Expr expr, Expr[] arguments) {
		this.expr = expr;
		this.arguments = arguments;
	}
}

interface IVisitor(T) {
	alias VisitResultType = T;

	T visit(BinaryExpr expr);
	T visit(PipeExpr expr);
	T visit(AssignExpr expr);
	T visit(UnaryExpr expr);
	T visit(CallExpr expr);
	T visit(MemberExpr expr);
	T visit(ImportStmt stmt);
	T visit(InlineDeclExpr expr);
	T visit(DeclExpr expr);
	T visit(DeclStmt stmt);
	T visit(Decl decl);
	T visit(StructDecl decl);
	T visit(FieldDecl decl);
	T visit(VarDecl decl);
	T visit(IdentifierExpr expr);
	T visit(LiteralExpr expr);
	T visit(ArrayLiteralExpr expr);
	T visit(Stmts stmt);
	T visit(ScopeStmt stmt);
	T visit(ExprStmt stmt);
	T visit(Program Program);
}

abstract class Visitor(T) : IVisitor!T {
	T visit(Node node) {
		import core.exception;
		throw new AssertError("Visitor " ~ typeof(this).stringof ~ " can not visit node of type " ~ node.classinfo.name);
	};
}

class NullVisitor(T) : Visitor!T {
	alias visit = Visitor!T.visit;

	T visit(BinaryExpr expr) { return T.init; }
	T visit(PipeExpr expr) { return T.init; }
	T visit(AssignExpr expr) { return T.init; }
	T visit(UnaryExpr expr) { return T.init; }
	T visit(CallExpr expr) { return T.init; }
	T visit(MemberExpr expr) { return T.init; }
	T visit(InlineDeclExpr expr) { return T.init; }
	T visit(DeclExpr expr) { return T.init; }
	T visit(DeclStmt stmt) { return T.init; }
	T visit(Decl decl) { return T.init; }
	T visit(StructDecl decl) { return T.init; }
	T visit(FieldDecl decl) { return T.init; }
	T visit(VarDecl decl) { return T.init; }
	T visit(IdentifierExpr expr) { return T.init; }
	T visit(ArrayLiteralExpr expr) { return T.init; }
	T visit(LiteralExpr expr) { return T.init; }
	T visit(Stmts stmt) { return T.init; }
	T visit(ScopeStmt stmt) { return T.init; }
	T visit(ImportStmt stmt) { return T.init; }
	T visit(ExprStmt stmt) { return T.init; }
	T visit(Program Program) { return T.init; }
}

Visitor.VisitResultType accept(Visitor)(Node node, auto ref Visitor visitor) {
	//writefln("Visit %s %s", node.nodeType, node);
	switch(node.nodeType) {
		foreach(NodeType; NodeTypes) {
			static if (is(typeof(visitor.visit(cast(NodeType)node))))
				case NodeType._nodeTypeId: return visitor.visit(cast(NodeType)node);
		}
		default:
		  import core.exception;
			throw new AssertError("Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
			//assert(0);//, "Visitor " ~ Visitor.stringof ~ " can not visit node of type " ~ node.classinfo.name);
			//assert(0, "NodeTypes does not contain all node types");
	}
}

import std.stdio: writefln;
import std.typetuple, std.traits;

Visitor[Visitor.length-1].VisitResultType accept(Visitor...)(Node node, auto ref Visitor visitors) if (Visitor.length > 1) {
	template getVisitorResultType(T) {
		alias getVisitorResultType = T.VisitResultType;
	}
	//alias ReturnTypes = staticMap!(ReturnType, staticMap!(getVisitor, Visitor));
	alias ReturnTypes = staticMap!(getVisitorResultType, Visitor);

	ReturnTypes R;
	foreach(i, visitor; visitors) {
		{	ReturnTypes[i] result;
			writefln("Visit using %s", typeof(visitor).stringof);
			static if (i == 0) {
				R[i] = node.accept(visitor);
			} else {
				R[i] = R[i-1].accept(visitor);
			}
		}
	}
	return R[R.length-1];
}
