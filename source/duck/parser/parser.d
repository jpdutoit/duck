module duck.compiler.parser;

import duck.compiler.token;
import duck.compiler.lexer;
import duck.compiler.ast;
import duck.compiler.types;


struct Parser {
	enum Precedence {
		Call = 140,
		MemberAccess = 140,
		Unary = 120,
		Multiplicative = 110,
		Additive = 100,
		Assignment = 30,
		Pipe  = 20
	};

	int rightAssociative(Token t) {
		switch (t.type) {
			case Symbol!"+=":;
			case Symbol!"=": return true;
			default:
				return false;
		}
	}

	int precedence(Token t) {
		switch (t.type) {
			case Identifier: return Precedence.Call;
			case Symbol!"(": return Precedence.Call;
			case Symbol!".": return Precedence.MemberAccess;
			case Symbol!"*": return Precedence.Multiplicative;
			case Symbol!"/": return Precedence.Multiplicative;
			case Symbol!"%": return Precedence.Multiplicative;
			case Symbol!"+": return Precedence.Additive;
			case Symbol!"-": return Precedence.Additive;
			case Symbol!"=>": return Precedence.Pipe;
			case Symbol!"=<": return Precedence.Pipe;
			case Symbol!"=": return Precedence.Assignment;
			case Symbol!"+=": return Precedence.Assignment;
			default:
			return -1;
		}
	}

	Lexer lexer;
	ParseError[] errors;

	this(String input) {
		lexer = Lexer(input);
	}

	Token expect(Token.Type tokenType, string message) {
		writefln("Expected %s found %s", tokenType, lexer.front.type);
		Token token = lexer.consume(tokenType);
		if (!token) {
			errors ~= new ParseError(lexer.front, message);
			import std.conv : to;
			throw new Exception("(" ~ lexer.input.lineNumber().to!string ~ ") " ~ message ~ " not '" ~ lexer.front.value.idup ~ "'");
			return None;
		}
		return token;
	}

	T expect(T)(T node, string message) if (is(T: Node)) {
		if (!node) {
			errors ~= new ParseError(lexer.front, message);
			import std.conv : to;
			throw new Exception("(" ~ lexer.input.lineNumber().to!string ~ ") " ~ message);
		}
		return node;
	}

	ArrayLiteralExpr parseArrayLiteral() {
		auto token = lexer.front;
		if (lexer.consume(Symbol!"[")) {
			Expr[] exprs;
			if (lexer.front.type != Symbol!"]") {
				exprs ~= expect(parseExpression(), "Expression expected");
				while (lexer.consume(Symbol!",")) {
					exprs ~= expect(parseExpression(), "Expression expected");
				}
			}
			expect(Symbol!"]", "Expected ']'");
			return new ArrayLiteralExpr(exprs);
		}
		return null;
	}
	Expr parsePrefix() {
		switch (lexer.front.type) {
				case Symbol!"[":
					return expect(parseArrayLiteral(), "Expected array literal.");
				default: break;
		}

		Token token = lexer.consume();
		switch(token.type) {
			case Number: {
				Expr literal = new LiteralExpr(token);
				// Unit parsing
				if (lexer.front.type == Identifier) {
					return new CallExpr(new IdentifierExpr(lexer.consume), [literal]);
				}
				return literal;
			}
			case StringLiteral:
				return new LiteralExpr(token);
			case Identifier:
				return new IdentifierExpr(token);
			case Symbol!"(": {
				// Grouping parentheses
				Expr expr = parseExpression();
				expect(Symbol!")", "Expected ')'");
				return expr;
				break;
			}
			case Symbol!"+":
			case Symbol!"-":
				return new UnaryExpr(token, parseExpression(Precedence.Unary - 1));
			default: break;
		}
		return null;
	}

	CallExpr parseCall(Expr target) {
		Expr[] arguments;
		if (lexer.front.type != Symbol!")") {
			arguments ~= parseExpression();
			while (lexer.consume(Symbol!",")) {
				arguments ~= parseExpression();
			}
		}
		expect(Symbol!")", "Expected ')'");
		return new CallExpr(target, arguments);
	}

	Expr parsePostfix(Expr left) {
		Token token = lexer.consume();
		//writefln("parseInfix: %s", token.value);
		int prec = precedence(token) + (rightAssociative(token) ? -1 : 0);
		switch (token.type) {
			case Identifier: {
				// Inline declaration
				CallExpr ctor;
				if (lexer.consume(Symbol!"(")) {
					ctor = parseCall(left);
				} else {
					ctor = new CallExpr(left, []);
				}
				return new InlineDeclExpr(token, new DeclStmt(token, new VarDecl(left, token), ctor));
				//return new InlineDeclExpr(token, new DeclStmt(token, new VarDecl(new NamedType(token, null)), ctor));
				break;
			}
			case Symbol!"(":
				// Call parenthesis
				return parseCall(left);
			case Symbol!".": {
				//writefln("%s %s", Identifier, Identifier);
				Token identifier = expect(Identifier, "Expected identifier following '.'");
				if (identifier) {
					return new MemberExpr(left, identifier);
				}
				break;
			}
			case Symbol!"=":
			case Symbol!"+=":
				return new AssignExpr(token, left, parseExpression(prec));
			case Symbol!"=>":
				return new PipeExpr(token, left, parseExpression(prec));
			case Symbol!"+":
			case Symbol!"-":
			case Symbol!"*":
			case Symbol!"/":
			case Symbol!"%":
				return new BinaryExpr(token, left, parseExpression(prec));
				//return factory.binaryOp(token, left, parseExpression(prec));
			default: break;
		}

		return null;
	}

	Expr parseExpression(int minPrecedence = 0) {
		//writefln("parseExpression: %s %s", lexer.front, minPrecedence);
		Expr left = parsePrefix();
		if (!left) return left;
		//writefln("Left: %s %s", left, lexer.front);

		while (precedence(lexer.front) > minPrecedence) {
			left = parsePostfix(left);
			//writefln("Left: %s %s", left, lexer.front);
		}
		return left;
	}

	Stmt parseBlock() {
		if (lexer.front.type == Symbol!"{") {
			lexer.consume();
			Stmt statements = parseStatements();
			lexer.expect(Symbol!"}", "Expected '}'");
			return statements;
		}
		return null;
	}

	FieldDecl parseField() {
		Token type = expect(Identifier, "Identifier expected");
		Token name = expect(Identifier, "Field name expected");

		return new FieldDecl(new IdentifierExpr(type), name);
		//return new FieldDecl(new NamedType(type.value.idup, new StructType(type)), name);
	}

	void parseGenerator() {
		bool isExtern = lexer.consume(Reserved!"extern") != None;
		lexer.expect(Reserved!"generator", "Expected generator");
		Token ident = expect(Identifier, "Expected identifier");
		expect(Symbol!"{", "Expected '}'");
		FieldDecl fields[];
		while (lexer.front.type != Symbol!"}") {
			fields ~= parseField();
			lexer.expect(Symbol!";", "Expected ';'");
		}
		expect(Symbol!"}", "Expected '}'");
		//new NamedType(ident.value.idup, new GeneratorType())
		auto generator = new GeneratorType(ident);
		Decl decl = new StructDecl(generator, ident, fields);
		generator.decl = decl;
		decls ~= decl;
	}

	ImportStmt parseImport() {
		lexer.expect(Reserved!"import", "Expected import");
		Token ident = expect(Identifier, "Expected identifier");
		lexer.expect(Symbol!";", "Expected ';'");
		return new ImportStmt(ident);
	}

	Stmt parseStatement() {
		switch (lexer.front.type) {
			case Reserved!"import":
				return parseImport();
			case Reserved!"extern":
			case Reserved!"generator":
				parseGenerator();
				return parseStatement();
			case Symbol!"{":
			  // Block statement
				return expect(parseBlock(), "Block expected");
			default: {
				// Expression statements
				Expr expr = parseExpression();
				if (expr) {
					lexer.expect(Symbol!";", "Expected ';'");
					return new ExprStmt(expr);
				}
				return null;
			}
		}
	}

	Stmt parseStatements(bool createScope = true) {
		Stmt[] statements;
		while (true) {
			Stmt stmt = parseStatement();
			if (!stmt)
				break;
			statements ~= stmt;
		}
		Stmts stmts = new Stmts(statements);
		return createScope ? new ScopeStmt(stmts) : stmts;
	}

	Program parseModule() {
		auto prog = new Program([parseStatements()], decls);
		lexer.expect(EOF, "Expected end of file");
		return prog;
	}

	Decl[] decls;
}

class ParseError {
	Token token;
	String message;

	this(Token token, String message) {
		this.token = token;
		this.message = message;
	}
}
