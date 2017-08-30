module duck.compiler.backend.d;
public import duck.compiler.backend.backend;

import duck.compiler.backend.d.codegen;

import duck.compiler.ast;
import duck.compiler.context: Context, ContextType;
import duck.compiler: DCode;
import duck.compiler.backend.d.dmd: DFile, DCompilerOptions;

import std.stdio;

class DBackend : Backend, SourceToBinaryCompiler {

  this(Context context) {
    super(context);
  }

  Executable compile(string[] engines = []) {
    auto dfile = genFile(context);
    dfile.context = context;
    if (context.hasErrors) return Executable("");

    if (context.options.instrument)
      dfile.options.merge(DCompilerOptions.Instrumentation);

    import std.algorithm.searching: canFind;

    version(OSX)
    if (engines.canFind("port-audio"))
      dfile.options.merge(DCompilerOptions.PortAudio);

    if (context.hasErrors) return Executable("");

    auto exe = dfile.compile();
    if (!exe) context.error("Internal compiler error.");
    return exe;
  }

  bool isExecutable() {
    return true;
  }
}

private DFile genFile(Context context) {
  Context.push(context);
  auto code = context.library.generateCode();
  Context.pop();

  if (context.hasErrors) return DFile();

  auto dfile = DFile.tempFromHash(context.isMain ? context.buffer.hashOf * 9129491 : context.buffer.hashOf);

  dfile.write(code);

  if (context.verbose)
    stderr.writeln("Compiled: ", context.buffer.path, " to ", dfile.filename);

  for (int i = 0; i < context.dependencies.length; ++i) {
    auto dep = genFile(context.dependencies[i]);
    dfile.options.merge(dep.options);
  }
  return dfile;
}
