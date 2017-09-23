module duck.compiler.context;

import std.exception : assumeUnique;
import std.stdio, std.conv;
import std.file : getcwd, isFile, exists;

import duck.util.stack: Stack;

import duck.compiler.lexer;
import duck.compiler.buffer;
import duck.compiler;

import std.path : dirName, baseName, buildNormalizedPath;
import duck.compiler.ast;

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

enum ContextType {
  root,
  main,
  library,
  stdlib
}

struct ContextOptions {
  bool instrument = false;
  bool includePrelude = true;
  bool verbose = false;
}

class Context {
  static Context[Buffer] cache;
  static Stack!Context stack = [];
  static void push(Context context) { stack.push(context); }
  static void pop() { stack.pop(); }

  ContextType type;
  string path;

  ContextOptions options;

  static Context createRootContext() {
    auto context = new Context();
    context.type = ContextType.root;
    context.path = getcwd();
    return context;
  }

  Context createStringContext(string code, ContextType type = ContextType.main) {
    auto buffer = new FileBuffer("", "-", false);
    buffer.contents = code ~ "\0";
    if (buffer in cache) return cache[buffer];

    Context context = createBufferContext(buffer, type);
    context.path = getcwd();
    context.packageRoots ~= getcwd();
    return context;
  }

  Context createStdlibContext(string relativeName = "prelude.duck", bool suppressErrors = false) {
    import core.runtime: Runtime;
    string filename = buildNormalizedPath(Runtime.args[0].dirName(), "../lib/duck_packages", relativeName);
    return createFileContext(filename, ContextType.stdlib, suppressErrors);
  }

  Context createFileContext(string filename, ContextType type = ContextType.main, bool suppressErrors = false) {
    if (!filename.exists || !filename.isFile) {
      if (!suppressErrors) this.error("Cannot find file \"" ~ filename ~ "\"");
      else if (this.verbose) stderr.writeln("Failed to load file: ", filename);
      return null;
    }
    if (this.verbose) stderr.writeln("Loaded file: ", filename);

    auto buffer = new FileBuffer(filename, true);
    if (buffer in cache) return cache[buffer];

    auto context = createBufferContext(buffer, type);
    context.path = buffer.path;
    context.packageRoots ~= filename.dirName;
    return context;
  }

  Context createImportContext(Slice target) {
    auto sourcePath = this.path;
    auto packageName = target ~ "/package.duck";
    auto filename = target ~ ".duck";
    import std.path : buildNormalizedPath;
    string path = "";

    // Handle local includes
    if (filename[0] == '.' || filename[0] == '/') {
      path = buildNormalizedPath(sourcePath, "..", filename);
      if (auto context = createFileContext(path, ContextType.library, true))
        return context;
    }
    else {
      // Check stdlib imports
      if (auto context = createStdlibContext(packageName, true)) return context;
      if (auto context = createStdlibContext(filename, true)) return context;

      // Handle package includes
      for (size_t i = 0; i < packageRoots.length; ++i) {
        path = buildNormalizedPath(packageRoots[i], "duck_packages", packageName);
        if (auto context = createFileContext(path, ContextType.library, true))
          return context;

        path = buildNormalizedPath(packageRoots[i], "duck_packages", filename);
        if (auto context = createFileContext(path, ContextType.library, true))
          return context;
      }
    }
    this.error(target, "Cannot find file at '" ~ path ~ "'");
    return null;
  }

  private Context createBufferContext(FileBuffer buffer, ContextType type) {
    auto context = new Context(buffer);

    context.type = type;
    context.options = this.options;
    context.options.includePrelude &= type != ContextType.stdlib;

    if (this.type != ContextType.root) {
      this.dependencies ~= context;
    }

    return Context.cache[buffer] = context;
  }

  this () { }

  this(Buffer buffer) {
    this();
    this.buffer = buffer;
  }

  @property
  bool isMain() { return this.type == ContextType.main; }

  @property
  Library library() {
    if (_library) {
      return _library;
    }
    _library = new Library(new Stmts(), []);

    auto phaseFlatten = Flatten();
    auto phaseSemantic = SemanticAnalysis(this, this.path);

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
    if (slice.buffer) {
      stderr.write(slice.toLocationString());
      stderr.write(": Error: ");
    } else {
      stderr.write("Error: ");
    }
    stderr.writeln(str);

    errors ~= CompileError(slice, str);
  }

  void info(Args...)(Slice slice, string formatString, Args args) {
    import std.format: format;
    info(slice, format(formatString, args));
  }

  void info(Slice slice, string str) {
    stderr.write(slice.toLocationString());
    stderr.write(": ");
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

  bool verbose() { return options.verbose; }
  Context[] dependencies;
  Buffer buffer;

  string[] packageRoots;
};
