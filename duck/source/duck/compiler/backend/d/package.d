module duck.compiler.backend.d;
public import duck.compiler.backend.backend;

import duck.compiler.backend.d.codegen;
import duck.compiler.backend.d.optimizer;

import duck.compiler.ast;
import duck.compiler.context: Context, ContextType;
import duck.compiler;
import duck.compiler.backend.d.dmd: DFile, DCompilerOptions;

import std.stdio;

class DBackend : Backend, SourceToBinaryCompiler {

  this(Context context) {
    super(context);
  }

  Executable compile(string[] engines = []) {
    auto dfile = genFile(context, new CodeGenContext(context));
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
    if (!exe) __ICE("Binary compilation failed");
    return exe;
  }

  bool isExecutable() {
    return true;
  }
}

private DFile genFile(Context library, CodeGenContext context) {
  Context.push(library);
  context.context = library;
  auto code = context.library.generateCode(context);
  Context.pop();

  if (context.hasErrors) return DFile();

  auto dfile = DFile.tempFromHash(context.isMain ? context.buffer.hashOf * 9129491 : context.buffer.hashOf);

  dfile.write(code);

  if (context.verbose)
    stderr.writeln("Compiled: ", context.buffer.path, " to ", dfile.filename);

  for (int i = 0; i < context.dependencies.length; ++i) {
    auto dep = genFile(context.dependencies[i], context);
    dfile.options.merge(dep.options);
  }
  return dfile;
}
