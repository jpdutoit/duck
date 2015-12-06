module duck.compiler;
import std.stdio : writefln, writeln;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.lexer, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
public import duck.compiler.buffer;


auto __ICE(string message = "", int line = __LINE__, string file = __FILE__) {
  import core.exception;
  import std.conv;
  import std.stdio;
  auto msg = "Internal compiler error: " ~ message ~ " at " ~ file ~ "(" ~ line.to!string ~ ") ";
  stderr.writeln(msg);
  return new AssertError(msg);
}


Program parseBuffer(Context context, Buffer buffer) {
  return Parser(context, buffer).parseModule();
}

struct SourceBuffer {
  Context context;
  Buffer buffer;

  this(Buffer buffer) {
    this.buffer = buffer;
    this.context = new Context();
  }
  AST parse() {
    auto phaseFlatten = Flatten();
    auto phaseSemantic = SemanticAnalysis(context, buffer.path);
    auto program = context.parseBuffer(buffer).flatten();

    program = program.accept(phaseSemantic);

    auto a = AST(context, program);
    return a;
  }
}

struct AST {
  Context context;

  this(Context context, Node program) {
    this.context = context;
    this.program = program;
  }

  DCode codeGen() {
    if (context.errors > 0) return DCode(null);
    //program.accept(ExprPrint());
    auto code = program.generateCode(context);

    //writefln("%s", code);

    auto s = q{import duck.runtime, duck.stdlib; }
    ~ "\n\nvoid start() {\n" ~ code ~ "\n}\n\n" 
    "void main(string[] args) {\n"
    "  initialize(args);\n"
    "  Duck(&start);\n"
    "  Scheduler.run();\n"
    "}\n";

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

int check(String filename) {
  auto ast = SourceBuffer(new FileBuffer(filename.idup)).parse();
  return ast.context.errors;
//  SourceCode(expression).parse();
}

auto compile(String filename) {
  return SourceBuffer(new FileBuffer(filename.idup)).parse().codeGen().code;
}
