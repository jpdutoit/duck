module host;

import duck.compiler;
import duck.host;
import std.file : getcwd;
import std.path : buildPath, dirName;
import std.stdio;
import std.algorithm.searching;
import duck.compiler.context;

import duck;

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
      Context context = Duck.contextForString(target);

      auto dfile = context.dfile();
      if (context.errors > 0) return context.errors;

      if (usePortAudio)
        dfile.options.merge(DCompilerOptions.PortAudio);

      auto proc = dfile.compile.execute();
    }
    else if (command == "check") {
      Context context = Duck.contextForFile(target);

      context.dcode;
      return context.errors;
    }
    else if (command == "run") {
      Context context = Duck.contextForFile(target);
      
      DFile dfile = context.dfile;

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
