module duck.compiler.context;

import std.exception : assumeUnique;
import std.stdio, std.conv;
import duck.compiler.lexer;
import duck.compiler.buffer;
import duck.compiler;

import std.path : buildPath, dirName, baseName;
import duck.compiler.ast;
import duck.host;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
import duck.compiler.dbg;

struct CompileError {
  Slice location;
  string message;
}

class Context {
  static Context current = null;

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

    Context previous = Context.current;
    Context.current = this;
    _library = cast(Library)(Parser(this, buffer)
      .parseLibrary()
      .flatten()
      .accept(phaseSemantic));
    Context.current = previous;

    for (int i = 0; i < dependencies.length; ++i) {
      dependencies[i].library;
    }

    return _library;
  }

  DCode dcode() {
    if (_dcode) {
      return _dcode;
    }

    //library.accept(ExprPrint());
    auto code = library.generateCode(this);

    if (this.hasErrors) return DCode(null);

    auto s =
    "import duck.runtime, duck.stdlib, core.stdc.stdio : printf;\n\n" ~
    code ~
    "\n";

    for (int i = 0; i < dependencies.length; ++i) {
      dependencies[i].dcode;
    }

    return _dcode = DCode(cast(string) s);
  }

  DFile dfile(bool isMainFile = true) {
    /*if (_dfile) {
      return _dfile;
    }*/
    auto code = dcode();

    _dfile = DFile.tempFromHash(isMainFile ? buffer.hashOf * 9129491 : buffer.hashOf);

    File dst = File(_dfile.filename, "w");
    dst.rawWrite(code.code);
    if (isMainFile) {
      dst.rawWrite(
        "\n\nvoid main(string[] args) {\n"
        "  initialize(args);\n"
        "  MainModule m;\n"
        "  Duck(&m.run);\n"
        "  Scheduler.run();\n"
        "}\n"
      );
    }
    dst.close();

    if (verbose)
      stderr.writeln("Compiled: ", buffer.path, " to ", _dfile.filename);

    _dfile.options.sourceFiles ~= _dfile.filename;
    for (int i = 0; i < dependencies.length; ++i) {
      _dfile.options.merge(dependencies[i].dfile(false).options);
    }

    return _dfile;
  }

  string moduleName() {
    if (_moduleName) {
      return _moduleName;
    }

    import std.digest.digest : toHexString;
    size_t hash = buffer.hashOf;
    ubyte[8] result = (cast(ubyte*) &hash)[0..8];
    _moduleName = ("duck_" ~ toHexString(result[0..8])).assumeUnique;

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

  protected DCode _dcode;
  protected Library _library;
  protected DFile _dfile;
  protected string _moduleName;

  bool instrument;

  DCompilerOptions compilerOptions;
  bool includePrelude;
  bool verbose = false;
  Context[] dependencies;
  Buffer buffer;

  string[] packageRoots;

  TempBuffer temp;
  int temporaries;
};
