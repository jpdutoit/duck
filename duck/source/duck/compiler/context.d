module duck.compiler.context;

import std.exception : assumeUnique;
import std.stdio, std.conv;

import duck.util.stack: Stack;

import duck.compiler.lexer;
import duck.compiler.buffer;
import duck.compiler;

import std.path : buildPath, dirName, baseName;
import duck.compiler.ast;
import duck.host;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
import duck.compiler.dbg;

@property
Context context() {
  return Context.stack.top;
}

struct CompileError {
  Slice location;
  string message;
}

class Context {
  static Stack!Context stack = [];
  static void push(Context context) { stack.push(context); }
  static void pop() { stack.pop(); }


  this () {
    temp = new TempBuffer("");
    import core.runtime;
    this.packageRoots ~= buildPath(Runtime.args[0].dirName(), "../lib");
    this.instrument = false;
  }

  this(Buffer buffer) {
    this();
    this.buffer = buffer;
  }

  Token token(Token.Type tokenType, string name) {
    return temp.token(tokenType, name);
  }

  Token temporary() {
    return token(Identifier, "__tmp" ~ (++temporaries).to!string);
  }


  @property
  Library library() {
    if (_library) {
      return _library;
    }
    _library = new Library(new Stmts(), []);

    auto phaseFlatten = Flatten();
    auto phaseSemantic = SemanticAnalysis(this, buffer.path);


    Context.push(this);

    _library = cast(Library)(Parser(this, buffer)
      .parseLibrary()
      .flatten()
      .accept(phaseSemantic));

    Context.pop();

    for (int i = 0; i < dependencies.length; ++i) {
      dependencies[i].library;
    }

    return _library;
  }

  string moduleName() {
    if (_moduleName) {
      return _moduleName;
    }

    import std.digest.digest : toHexString;
    size_t hash = buffer.hashOf;
    ubyte[8] result = (cast(ubyte*) &hash)[0..8];
    _moduleName = ("_duck_" ~ toHexString(result[0..8])).assumeUnique;

    return _moduleName;
  }

  void error(Args...)(Slice slice, string formatString, Args args) {
    import std.format: format;
    error(slice, format(formatString, args));
  }

  void error(Slice slice, string str) {
    stderr.write(slice.toLocationString());
    stderr.write(": Error: ");
    stderr.writeln(str);

    errors ~= CompileError(slice, str);
  }

  void error(string str) {
    stderr.write("Error: ");
    stderr.writeln(str);

    errors ~= CompileError(Slice(), str);
  }

  bool hasErrors() { return errors.length > 0; }
  CompileError[] errors = [];

  protected Library _library;
  protected string _moduleName;

  bool instrument;

  bool includePrelude;
  bool verbose = false;
  Context[] dependencies;
  Buffer buffer;

  string[] packageRoots;

  TempBuffer temp;
  int temporaries;
};
