module host;

import duck.compiler;
import duck.host;
import std.file : getcwd;
import std.path : buildPath, dirName;
import std.stdio;
import std.algorithm.searching;
import duck.compiler.context;

version (D_Coverage) {
  extern (C) void dmd_coverDestPath(string);
  extern (C) void dmd_coverSourcePath(string);
  extern (C) void dmd_coverSetMerge(bool);
}

void printHelp() {
      writefln("""duck

Usage:
duck run [--no-port-audio] file
duck check file
""");
}
int main(string[] args) {
  version(D_Coverage) {
    dmd_coverSourcePath(".");
    dmd_coverDestPath("coverage");
    dmd_coverSetMerge(true);
  }

  auto builtinPackagePath = buildPath(args[0].dirName(), "../lib");
  Context context = new Context();
  context.packageRoots ~= builtinPackagePath.idup;

  bool usePortAudio = true;
  int index = 1;
  string command;
  string target;
  for (;index < args.length; ++index) {
    if (!command && args[index] == "--help" || args[index] == "-h") {
      printHelp();
      return 0;
    }
    else 
    if ((command == "exec" || command == "run") && args[index] == "--no-port-audio") {
      usePortAudio = false;
    }
    else
    if (args[index].startsWith("-")) {
      stderr.writeln("Unrecognized option: ", args[index]);
      return 1;
    }
    else {
      if (command) {
        if (target) {
          stderr.writeln("Unrecognized parameter: ", args[index]);
          return 1;
        } else {
          target = args[index];
        }
      }
      else {
        command = args[index];
      }
    }
  }
  if (command) {
    if (!target) {
      writeln("No target");
      return 1;
    }

    if (command == "exec") {
      auto buffer = SourceBuffer(new FileBuffer("", getcwd() ~ "/argument", false));
      buffer.buffer.contents = "import \"prelude\";" ~ target ~ "\0";
      context.packageRoots ~= getcwd().idup;
      buffer.context = context;
      //writeln(buffer.buffer.contents);

      auto ast = buffer.parse();
      if (ast.context.errors > 0) return ast.context.errors;
      auto dfile = ast.codeGen().saveToTemporary;
      if (usePortAudio)
        dfile.options.merge(DCompilerOptions.PortAudio);

      auto proc = dfile.compile.execute();
    }
    else if (command == "check") {
        context.packageRoots ~= target.dirName().idup();

        auto buffer = SourceBuffer(target);
        buffer.context = context;
        auto ast = buffer.parse();
        
        ast.codeGen();
        return ast.context.errors;
    }
    else if (command == "run") {
      context.packageRoots ~= target.dirName().idup();

      auto buffer = SourceBuffer(target);
      buffer.context = context;
      auto ast = buffer.parse();
      if (ast.context.errors > 0) return ast.context.errors;
      auto dfile = ast.codeGen().saveToTemporary;

      if (usePortAudio)
        dfile.options.merge(DCompilerOptions.PortAudio);

      auto proc = dfile.compile.execute();
      proc.wait();
    }
    else {
      writeln("Unexpected command: ", command);
      return 1;
    }
  }
  if (!command) {
    printHelp();
  }
  return 0;
}
