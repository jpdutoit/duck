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


class Context {
  this () {
    temp = new TempBuffer("");
    import core.runtime;
    this.packageRoots ~=  buildPath(Runtime.args[0].dirName(), "../lib");
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
    _library = new Library([], []);

    auto phaseFlatten = Flatten();
    auto phaseSemantic = SemanticAnalysis(this, buffer.path);

    _library = cast(Library)(Parser(this, buffer)
      .parseLibrary()
      .flatten()
      .accept(phaseSemantic));

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

    if (this.errors > 0) return DCode(null);
    
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
        "  Duck(&start);\n"
        "  Scheduler.run();\n"
        "}\n"
      );
    }
    dst.close();

    //debug(verbose)
      writeln("SAVED: ", _dfile.filename, " (", buffer.path, ")");

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
 
  void error(Args...)(Slice slice, string format, Args args)
  {
    errors++;

    stderr.write(slice.toLocationString());
    stderr.write(": Error: ");
    stderr.writefln(format, args);
  }

  void error(Slice slice, string str) {
    errors++;

    stderr.write(slice.toLocationString());
    stderr.write(": Error: ");
    stderr.writeln(str);
  }


  protected DCode _dcode;
  protected Library _library;
  protected DFile _dfile;
  protected string _moduleName;

  DCompilerOptions compilerOptions;
  bool includePrelude;
  Context[] dependencies;
  Buffer buffer;

  string[] packageRoots;

  TempBuffer temp;
  int errors;
  int temporaries;
};
