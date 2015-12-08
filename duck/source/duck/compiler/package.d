module duck.compiler;
import std.stdio : writefln, writeln;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.lexer, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
public import duck.compiler.buffer;

Program parseBuffer(Context context, Buffer buffer) {
  return Parser(context, buffer).parseModule();
}

struct SourceBuffer {
  Context context;
  Buffer buffer;
  
  this(string filename) {
    this.buffer = new FileBuffer(filename);
    this.context = new Context();
  }
  this(Buffer buffer) {
    this.buffer = buffer;
    this.context = new Context();
  }
}

struct AST {
  Context context;

  this(Context context, Node program) {
    this.context = context;
    this.program = program;
  }

  Node program;
};

struct DCode {
  this(String code) {
    this.code = code;
  }
  String code;
}

AST parse(SourceBuffer source) {
  auto phaseFlatten = Flatten();
  auto phaseSemantic = SemanticAnalysis(source.context, source.buffer.path);
  auto program = source.context.parseBuffer(source.buffer).flatten();

  program = program.accept(phaseSemantic);

  return AST(source.context, program);
}

DCode codeGen(AST ast) {
  if (ast.context.errors > 0) return DCode(null);
  //program.accept(ExprPrint());
  auto code = ast.program.generateCode(ast.context);
  //writeln(code);
  auto s =
  "import duck.runtime, duck.stdlib;\n\n"
  "void start() {\n" ~
  code ~
  "\n}\n\n"
  "void main(string[] args) {\n"
  "  initialize(args);\n"
  "  Duck(&start);\n"
  "  Scheduler.run();\n"
  "}\n";

  return DCode(cast(String)s);
}

int check(String filename) {
  auto ast = SourceBuffer(new FileBuffer(filename.idup)).parse();
  return ast.context.errors;
//  SourceCode(expression).parse();
}

auto compile(String filename) {
  return SourceBuffer(new FileBuffer(filename.idup)).parse().codeGen().code;
}
