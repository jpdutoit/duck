module duck.compiler.backend.d;
public import duck.compiler.backend.backend;

import duck.compiler.backend.d.codegen;

import duck.compiler.ast;
import duck.compiler.context: Context;
//import duck.host: DFile, DCompilerOptions;
import duck.compiler: DCode;
import duck.compiler.backend.d.dmd: DFile, DCompilerOptions;

import std.stdio;

class DBackend : Backend, SourceToBinaryCompiler {

  this(Context context) {
    super(context);
  }

  Executable compile(string[] engines = []) {
    auto dfile = genFile(context, true);
    if (context.hasErrors) return Executable("");

    if (context.instrument)
      dfile.options.merge(DCompilerOptions.Instrumentation);

    import std.algorithm.searching: canFind;

    version(OSX)
    if (engines.canFind("port-audio"))
      dfile.options.merge(DCompilerOptions.PortAudio);

    if (context.hasErrors) return Executable("");

    return dfile.compile();
  }

  bool isExecutable() {
    return true;
  }
}

private DFile genFile(Context context, bool isMainFile) {
  auto code = generateCode(context.library, context, isMainFile);
//  if (context.hasErrors) return DCode(null);
  auto dfile = DFile.tempFromHash(isMainFile ? context.buffer.hashOf * 9129491 : context.buffer.hashOf);

  File dst = File(dfile.filename, "w");
  dst.rawWrite(code);
  dst.close();

  if (context.verbose)
    stderr.writeln("Compiled: ", context.buffer.path, " to ", dfile.filename);

  dfile.options.sourceFiles ~= dfile.filename;
  for (int i = 0; i < context.dependencies.length; ++i) {
    auto dep = genFile(context.dependencies[i], false);
    dfile.options.merge(dep.options);
  }
  return dfile;
}
