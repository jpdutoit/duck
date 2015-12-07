module host;

import duck.compiler;
import duck.host;
import std.stdio;
import std.algorithm.searching;

version (D_Coverage) {
  extern (C) void dmd_coverDestPath(string);
  extern (C) void dmd_coverSourcePath(string);
  extern (C) void dmd_coverSetMerge(bool);
}
int main(string[] args) {
  version(D_Coverage) {
    dmd_coverSourcePath(".");
    dmd_coverDestPath("coverage");
    dmd_coverSetMerge(true);
  }

  bool usePortAudio = true;
  int index = 1;
  string command;
  string target;
  for (;index < args.length; ++index) {
    if (command == "run" && args[index] == "--no-port-audio") {
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

  if (command && target) {
      if (command == "check") {
          auto ast = SourceBuffer(new FileBuffer(target)).parse();
          ast.codeGen();
          return ast.context.errors;
      }
      else if (command == "run") {
        auto ast = SourceBuffer(new FileBuffer(target)).parse();
        if (ast.context.errors > 0) return ast.context.errors;
        auto dfile = ast.codeGen().saveToTemporary;

        if (usePortAudio)
          dfile.options.merge(DCompilerOptions.PortAudio);

        auto proc = dfile.compile.execute();
        proc.wait();
      }
      else return 1;
  }
  return 0;
}
