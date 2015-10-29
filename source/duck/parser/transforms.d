module duck.compiler.transforms;

import duck.compiler.ast, duck.compiler.token, duck.compiler.visitors;

class TransformVisitor : Visitor!Node {
	alias accept = transform;
	final void transform(Target)(ref Target target) {
		auto obj = target.accept(this);
		assert(cast(Target)obj, "expected " ~ typeof(this).stringof ~ ".visit(" ~ Target.stringof ~ ") to return a " ~ Target.stringof);
		target = cast(Target)obj;
		//return obj;
	}

	alias visit = Visitor!Node.visit;

	Node visit(BinaryExpr expr) {
		transform(expr.left);
		transform(expr.right);
		return expr;
	}

	Node visit(PipeExpr expr) {
		transform(expr.left);
		transform(expr.right);
		return expr;
	}

	Node visit(AssignExpr expr) {
		transform(expr.left);
		transform(expr.right);
		return expr;
	}

	Node visit(UnaryExpr expr) {
		transform(expr.operand);
		return expr;
	}

	Node visit(CallExpr expr) {
		foreach (i, ref arg ; expr.arguments) {
			transform(arg);
		}
		transform(expr.expr);
		return expr;
	}

	Node visit(MemberExpr expr) {
		transform(expr.expr);
		return expr;
	}

	Node visit(DeclExpr expr) {
		transform(expr.decl);
		return expr;
	}

	Node visit(InlineDeclExpr expr) {
		transform(expr.declStmt);
		return expr;
	}

	Node visit(DeclStmt stmt) {
		transform(stmt.decl);
		transform(stmt.expr);
		return stmt;
	}

	Node visit(StructDecl decl) {
		foreach(ref field; decl.fields) {
			transform(field);
		}
		return decl;
	}

	Node visit(FieldDecl decl) {
		transform(decl.typeExpr);
		return decl;
	}

	Node visit(VarDecl decl) {
		transform(decl.typeExpr);
		return decl;
	}

	Node visit(Decl decl) {
		//transform(decl.expr);
		return decl;
	}
	Node visit(IdentifierExpr expr) {
		return expr;
	}
	Node visit(ArrayLiteralExpr expr) {
		foreach (i, ref expr1 ; expr.exprs) {
			transform(expr1);
		}
		return expr;
	}
	Node visit(LiteralExpr expr) {
		return expr;
	}
	Node visit(Stmts stmt) {
		foreach (i, ref stmt1 ; stmt.stmts) {
			transform(stmt1);
		}
		return stmt;
	}
	Node visit(ImportStmt stmt) {
		return stmt;
	}

	Node visit(ScopeStmt stmt) {
		transform(stmt.stmts);
		return stmt;
	}
	Node visit(ExprStmt stmt) {
		transform(stmt.expr);
		return stmt;
	}
	Node visit(Program program) {
		foreach (ref node ; program.nodes) {
			transform(node);
		}
		return program;
	}
}

/*
class ConstantLift : TransformVisitor {
	DeclStmt decls[];
	int tmpCount;

	alias visit = TransformVisitor.visit;

	override Node visit(LiteralExpr expr) {
		if (expr.token.type == Number) {
			import std.conv;
			String name = "_num_" ~ (tmpCount++).to!String;
			if (expr.token.type == Number) {
				String type = "Float";
				decls ~= new DeclStmt(new DeclExpr(
					Token(Identifier, name, 0, cast(int)name.length),
					new VarDecl(null),
					new CallExpr(new IdentifierExpr(Token(Identifier, type, 0, cast(int)type.length)), [expr])
					));
			}
			else {
				decls ~= new DeclStmt(new Decl(Token(Identifier, name, 0, cast(int)name.length), expr));
			}
			return new IdentifierExpr(Token(Identifier, name, 0, cast(int)name.length));
		}
		return expr;
	}

	override Node visit(Program program) {
		super.visit(program);
		program.nodes = cast(Node[])decls ~ program.nodes;
		return program;
	}
};*/

/*class WrapFunc : TransformVisitor {
	override Node visit(CallExpr expr) {
		if (expr.arguments.length == 1) {
			if (cast(LiteralExpr)expr.arguments[0]) {
				return expr;
			}

		}
		return expr;
	}
}
*/
class InlineDeclLift : TransformVisitor {
	DeclStmt decls[];
	alias visit = TransformVisitor.visit;

	override Node visit(InlineDeclExpr expr) {
		decls ~= expr.declStmt;
		return new IdentifierExpr(expr.token);
	}

	override Node visit(ExprStmt stmt) {
		decls = [];
		if (auto declExpr = cast(InlineDeclExpr) stmt.expr) return declExpr.declStmt;
		super.visit(stmt);
		if (decls.length > 0) {
			return new Stmts(cast(Stmt[])decls ~ stmt);
		}
		return stmt;
	}
}


  // A * (B >> C) >> D => B >> C; A * C >> D;
  // (A >> B) >> C => A >> B; B >> C;
  // A >> (B >> C) => B >> C; A >> C;
class PipeSplit : TransformVisitor {
	alias visit = TransformVisitor.visit;

	Stmt[] stmts;
	int depth = 0;

	override Node visit(PipeExpr pipe) {
		depth++;
		accept(pipe.left);
		accept(pipe.right);
		depth--;

		if (depth > 0) {
			stmts ~= new ExprStmt(pipe);
			return pipe.right;
		}
		return pipe;
	}

	override Node visit(ExprStmt stmt) {
		stmts = [];
		//if (auto declExpr = cast(InlineDeclExpr) stmt.expr) return declExpr.declStmt;
		accept(stmt.expr);
		if (stmts.length > 0) {
			return new Stmts(cast(Stmt[])stmts ~ stmt);
		}
		return stmt;
	}
}

class Flatten : TransformVisitor {
	alias visit = TransformVisitor.visit;

	void merge(ref Stmt[] all, Stmt stmt) {
		if (auto stmts = cast(Stmts)stmt) {
			foreach(s; stmts.stmts) {
				merge(all, s);
			}
		} else {
			all ~= stmt;
		}
	}
	override Node visit(Stmts stmts) {
		Stmt[] all;
		merge(all, stmts);
		stmts.stmts = all;
		return stmts;
	}
}

class ResolveImports : TransformVisitor {
	alias visit = TransformVisitor.visit;

	Program program;
	override Node visit(Program program) {
		this.program = program;
		return super.visit(program);
	}

	override Node visit(ImportStmt stmt) {
		import duck.compiler;
		writefln("Import %s.duck", stmt.identifier.value);
		auto AST = SourceCode(loadFile(stmt.identifier ~ ".duck")).parse();
		if (auto program = cast(Program)AST.program) {
			this.program.decls ~= program.decls;
		}
		return new Stmts([]);
	}
}

class ConstantFold : TransformVisitor {
	alias visit = TransformVisitor.visit;

	override Node visit(BinaryExpr binary) {
		super.visit(binary);

		LiteralExpr left = cast(LiteralExpr)binary.left;
		LiteralExpr right = cast(LiteralExpr)binary.right;
		if (left && right && left.token.type == Number && right.token.type == Number) {
			import std.conv;
			real a = left.token.value.to!real();
			real b = right.token.value.to!real();
			real c;
			switch(binary.operator.type) {
				case Symbol!"-": c = a - b; break;
				case Symbol!"+": c = a + b; break;
				case Symbol!"*": c = a * b; break;
				case Symbol!"/": c = a / b; break;
				default: return binary;
			}
			auto s = c.to!String();
			return new LiteralExpr(Token(Number, s, 0, cast(int)(s.length)));
		}
		return binary;
	}

	override Node visit(UnaryExpr unary) {
		super.visit(unary);

		LiteralExpr operand = cast(LiteralExpr)unary.operand;
		if (operand && operand.token.type == Number) {
			import std.conv;
			real a = operand.token.value.to!real();
			real c;
			switch(unary.operator.type) {
				case Symbol!"-": c = -a; break;
				case Symbol!"+": c = +a; break;
				default: return unary;
			}
			auto s = c.to!String();
			return new LiteralExpr(Token(Number, s, 0, cast(int)(s.length)));
		}
		return unary;
	}
}
