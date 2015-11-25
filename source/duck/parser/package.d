module duck.compiler;
import std.stdio : writefln, writeln;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.token, duck.compiler.visitors, duck.compiler.semantic;



version(unittest) {
	void assertExpressionParse(String expr, String expectedParsed) {
		auto parser = Parser(expr);
		String parsed = parser.parseExpression().accept(ExprToString());

		if (expectedParsed != parsed) {
			writefln("Input:    %s\nResult:   %s\nExpected: %s", expr, parsed, expectedParsed);
			assert(expectedParsed == parsed);
		}
	}
	void assertStatementsParse(String expr, String expectedParsed) {
		auto parser = Parser(expr);
		String parsed = parser.parseStatements().accept(ExprToString());

		//auto parser = Parser!ExprString(expr);
		//String parsed = parser.parseStatements();
		if (expectedParsed != parsed) {
			writefln("Input:    %s\nResult:   %s\nExpected: %s", expr, parsed, expectedParsed);
			assert(expectedParsed == parsed);
		}
	}

	/*void assertExpressionCodeGen(String expr, String expectedParsed) {
		auto parser = Parser!CodeGen(expr);
		String parsed = parser.parseExpression();
		if (expectedParsed != parsed) {
			writefln("Input:    %s\nResult:   %s\nExpected: %s", expr, parsed, expectedParsed);
			assert(expectedParsed == parsed);
		}
	}*/
}

Expr parseExpression(String expression) {
	return Parser(expression).parseExpression();
}


Stmt parseStatements(String expression) {
	return Parser(expression).parseStatements();
}


Program parseModule(String expression) {
	return Parser(expression).parseModule();
}


String loadFile(String filename) {
	import std.stdio;
	char buffer[1024*1024];

	// Read input file
	File src = File(filename.idup, "r");
	auto buf = src.rawRead(buffer);
	src.close();
	return buf;
}

struct SourceCode {
	this(String code) {
		this.code = code;
	}

	AST parse() {
		return AST(code.parseModule().accept(new InlineDeclLift(), new PipeSplit(), new Flatten(), new ResolveImports(), new SemanticAnalysis()));
	}
	String code;
}

struct AST {
	this(Node program) {
		this.program = program;
	}

	DCode codeGen() {
		auto code = program.accept(ExprPrint(),/*new ConstantLift(),*/ CodeGen());

		writefln("%s", code);

		auto s = q{import duck.runtime, duck.stdlib, std.stdio; }
		~ "void start() { " ~ code ~ "\n}" ~
		q{
			void main(string[] args) {
				initialize(args);
				Duck(&start);
				Scheduler.run();
			}
		};

		return DCode(cast(String)s);
	}

	Node program;
};

struct DCode {
	this(String code) {
		this.code = code;
	}
	String code;
}

auto compile(String expression) {
	return SourceCode(expression).parse().codeGen().code;
	/+auto code = expression.parseModule().accept(new InlineDeclLift(), new PipeSplit(), new Flatten(), new SemanticAnalysis(), ExprPrint(),/*new ConstantLift(),*/ CodeGen());

	writefln("%s", code);
	return
	q{import duck, std.stdio, duck.global, duck.types;}
	~ "void start() { " ~ code ~ "writefln(\"Hello\");\n}" ~
	q{
		void main() {
			Duck(&start);
		}
	};
	//return null;+/
}

unittest {
return;
	assertExpressionParse("\"abcd\"", "\"abcd\"");
	assertExpressionParse("1", "1");
	assertExpressionParse("1.23 hz", "hz(1.23)");
	assertExpressionParse("a", "a");
	assertExpressionParse("a.b.c", "((a.b).c)");
	assertExpressionParse("a.b.c()", "((a.b).c)()");
	assertExpressionParse("a.b.c(1,2)", "((a.b).c)(1,2)");
	assertExpressionParse("(1)", "1");
	assertExpressionParse("bcd", "bcd");
	assertExpressionParse("1+2", "(1+2)");
	assertExpressionParse("abc+def", "(abc+def)");
	assertExpressionParse("a+b*c+d", "((a+(b*c))+d)");
	assertExpressionParse("(a+b)*(c+d)", "((a+b)*(c+d))");
	assertExpressionParse("a-b/c-d", "((a-(b/c))-d)");
	assertExpressionParse("a*b*c", "((a*b)*c)");
	assertExpressionParse("a/b/c", "((a/b)/c)");
	assertExpressionParse("a=b=c", "(a=(b=c))");
	assertExpressionParse("j=--a+b*c+d/e/f=g", "(j=((((-(-a))+(b*c))+((d/e)/f))=g))");

	//assertStatementsParse("1+2;3+4;", "{(1+2);(3+4);}");
	//assertStatementsParse("{1+2;3+4;{5+6;}}", "{{(1+2);(3+4);{(5+6);};};}");
	//assertExpressionCodeGen("1+2+a+c", "");
	{

		//enum parser = Parser("1+a+b+4+c");
		auto a = 10, b= 20, c=30;
		//auto value ="1+2+3+4+a+b+4+c(1,2,g)".parseExpression().accept(Transform!(Transform!DynamicConstant, Transform!ConstantFold, StringVisitor)());
		//auto value ="-1+2*3+4/5+a+b+4+c(1,2,g)".parseExpression().accept(ExprPrint(), ConstantFold(), ExprPrint());
		auto value ="1+2+3+4+5".parseExpression().accept(ExprPrint(), new ConstantFold(), ExprPrint());

		writefln("[[[[[");
		auto aaaa = "a(1) + 2 + SinOsc s => c;".parseModule().accept(ExprPrint(), new InlineDeclLift(), ExprPrint(), new ConstantLift(), ExprPrint(), new ConstantFold(), ExprPrint(), CodeGen());
		writefln("]]]]] %s", aaaa);
		//pragma(msg, " = " , value);
		writefln("parsed: %s", value);
		//mixin("SinOsc a; SinOsc b; SinOsc c;" ~ parsed ~ ";");
	}
	/*assertParse("//Float a;Float b;", "//Float a;Float b;");
	assertParse("//Float a;Float b;\n", "//Float a;Float b;\n");
	assertParse("Float a;\nFloat b;\n", "Float a;\nFloat b;\n");
	assertParse("Float b;\n", "Float b;\n");

	assertParse("Float a; //Float a;Float b;", "Float a; //Float a;Float b;");
	assertParse("Float a >> Float b;\n", "Float a;Float b;a >> b;\n");
	assertParse("Float a; a >> Float b;\n", "Float a;Float b; a >> b;\n");
	assertParse("Float b; Float a >> b;\n", "Float b;Float a; a >> b;\n");*/
}
