module duck.compiler;
import std.stdio : writefln, writeln;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.lexer, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
import duck.compiler.dbg;
public import duck.compiler.buffer;

Library parseBuffer(Context context, Buffer buffer) {
  return Parser(context, buffer).parseLibrary();
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

  this(Context context, Library library) {
    this.context = context;
    this.library = library;
  }

  Library library;
};

struct DCode {
  this(string code) {
    this.code = code;
  }
  string code;
}

AST parse(SourceBuffer source) {
  auto phaseFlatten = Flatten();
  auto phaseSemantic = SemanticAnalysis(source.context, source.buffer.path);
  Library library = cast(Library)source.context
    .parseBuffer(source.buffer)
    .flatten()
    .accept(phaseSemantic);

  enforce(library, __ICE("AST is null"));

  return AST(source.context, library);
}

DCode codeGen(AST ast) {
  if (ast.context.errors > 0) return DCode(null);
  //library.accept(ExprPrint());
  auto code = ast.library.generateCode(ast.context);
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

  return DCode(cast(string)s);
}

int check(string filename) {
  auto ast = SourceBuffer(new FileBuffer(filename.idup)).parse();
  return ast.context.errors;
//  SourceCode(expression).parse();
}

auto compile(string filename) {
  return SourceBuffer(new FileBuffer(filename.idup)).parse().codeGen().code;
}
