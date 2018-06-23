module duck.compiler.context;

import duck.compiler;
import duck.compiler.semantic;

import duck.util.stack: Stack;

import std.stdio;
import std.file : getcwd, isFile, exists;
import std.path : dirName, buildNormalizedPath;

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
  builtin,
  main,
  library,
  stdlib
}

struct ContextOptions {
  bool instrument = false;
  bool includePrelude = true;
  bool verbose = false;
  bool treeshake = true;
}

private string _stdlibPath;
string stdlibPath() {
  if (_stdlibPath) return _stdlibPath;
  import core.runtime: Runtime;
  _stdlibPath = buildNormalizedPath(Runtime.args[0].dirName(), "../runtime/duck_packages");
  return _stdlibPath;
}

class Context {
  static Context[Buffer] cache;
  static Stack!Context stack = [];
  static void push(Context context) { stack.push(context); }
  static void pop() { stack.pop(); }

  immutable ContextType type;
  immutable string moduleName;
  string path;

  ContextOptions options;

  static Context createRootContext() {
    return new Context(ContextType.root, "__root", getcwd());
  }

  Context createBuiltinContext() {
    auto context = new Context(ContextType.builtin, "__builtin", getcwd());
    Context.push(context);
    auto phaseSemantic = SemanticAnalysis(context);
    context._library = Library.builtins;
    phaseSemantic.semantic(context._library);
    Context.pop();
    if (this.type != ContextType.root) {
      this.dependencies ~= context;
    }
    return context;
  }

  Context createStringContext(string code, ContextType type = ContextType.main) {
    auto filename = buildNormalizedPath(getcwd(), "-");
    auto buffer = new FileBuffer(filename, code ~ "\0");
    return createBufferContext(type, buffer);
  }

  Context createStdlibContext(string relativeName = "prelude.duck", bool suppressErrors = false) {
    string filename = buildNormalizedPath(stdlibPath, relativeName);
    return createFileContext(filename, ContextType.stdlib, suppressErrors);
  }

  Context createFileContext(string filename, ContextType type = ContextType.main, bool suppressErrors = false) {
    if (!filename.exists || !filename.isFile) {
      if (!suppressErrors) this.error("Cannot find file \"" ~ filename ~ "\"");
      else if (this.verbose) stderr.writeln("Failed to load file: ", filename);
      return null;
    }

    auto buffer = new FileBuffer(filename);
    if (this.verbose) stderr.writeln("Loaded file: ", filename);

    if (buffer in cache) return cache[buffer];
    return createBufferContext(type, buffer);
  }

  Context createImportContext(Slice target) {
    auto sourcePath = this.path;
    auto packageName = target ~ "/package.duck";
    auto filename = target ~ ".duck";
    import std.path : buildNormalizedPath;
    string path = "";

    // Handle local includes
    if (filename[0] == '.' || filename[0] == '/') {
      path = buildNormalizedPath(sourcePath, filename);
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

  private Context createBufferContext(ContextType type, FileBuffer buffer) {
    auto context = new Context(type, buffer);

    context.options = this.options;
    context.options.includePrelude &= type != ContextType.stdlib;

    if (this.type != ContextType.root) {
      this.dependencies ~= context;
    }

    return Context.cache[buffer] = context;
  }

  protected this(ContextType type, string moduleName, string path) {
    this.type = type;
    this.moduleName = moduleName;
    this.path = path;
    this.packageRoots ~= path;
  }

  protected this(ContextType type, Buffer buffer) {
    this(type, "_duck_" ~ buffer.hashString, buffer.dirname);
    this.buffer = buffer;
  }

  @property
  bool isMain() { return this.type == ContextType.main; }

  @property
  Library library() {
    if (_library) {
      return _library;
    }

    Context.push(this);
    auto phaseSemantic = SemanticAnalysis(this);

    _library = Parser(this, buffer).parseLibrary();
    phaseSemantic.semantic(_library);

    Context.pop();

    for (int i = 0; i < dependencies.length; ++i) {
      dependencies[i].library;
    }

    return _library;
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

  bool verbose() { return options.verbose; }
  Context[] dependencies;
  Buffer buffer;

  string[] packageRoots;
};
