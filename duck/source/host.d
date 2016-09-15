module host;

immutable VERSION = import("VERSION");

import duck.compiler;
import duck.host;
import std.file : getcwd;
import std.path : buildPath, dirName;
import std.stdio;
import std.algorithm.searching;
import duck.compiler.context;
import std.getopt, std.array;
import std.c.stdlib : exit;

import duck;

version (D_Coverage) {
  extern (C) void dmd_coverDestPath(string);
  extern (C) void dmd_coverSourcePath(string);
  extern (C) void dmd_coverSetMerge(bool);
}

void printHelp(GetoptResult result, string error = null) {
  defaultGetoptPrinter(
    "Duck " ~ VERSION ~ "\n"
    "Usage:\n"
    "  duck { options } target.duck\n"
    "or\n"
    "  duck { options } -- \"duck code\"\n",
    result.options);
  if (error) {
    stderr.writeln("\nError: ",error);
  }
  exit(1);
}

GetoptResult getopt(T...)(ref string[] args, T opts) {
  try {
    return std.getopt.getopt(args, opts);
  }
  catch(GetOptException e) {
    string[] tmp = [args[0]];
    auto result = std.getopt.getopt(tmp, opts);
    printHelp(result, e.msg);
    return result;
  }
}

int main(string[] args) {
  version(D_Coverage) {
    dmd_coverSourcePath(".");
    dmd_coverDestPath("coverage");
    dmd_coverSetMerge(true);
  }
  version(unittest) {
    return 0;
  }
  else {

    bool verbose = false;
    bool compileOnly = false;
    //bool forever = false;
    bool noStdLib = false;
    string[] engines = [];

    auto result = getopt(
      args,
      std.getopt.config.bundling,
      std.getopt.config.keepEndOfOptions,
      "nostdlib|b|bare", "Do not automatically import the standard library", &noStdLib,
      "engine|e", "Audio engines: null, port-audio", &engines,
      //"forever|f", "Run forever", &forever,
      "compile|c", "Compile only / do not run", &compileOnly,
      "verbose|v", "Verbose output", &verbose
    );

    // Set default audio engines
    if (engines.length == 0) {
      engines = ["port-audio"];
    }

    if (result.helpWanted || args.length == 1) {
      printHelp(result);
    }

    if (args.length < 2) {
        printHelp(result, "No target");
    }

    Context context;
    if (args[1] == "--") {
      context = Duck.contextForString(args[2..$].join(" "));
    } else {
      context = Duck.contextForFile(args[1]);
    }
    if (context.errors > 0) return context.errors;

    context.verbose = verbose;
    context.includePrelude = !noStdLib;

    context.library;
    if (context.errors > 0) return context.errors;

    if (!compileOnly) {
      auto dfile = context.dfile();
      if (context.errors > 0) return context.errors;

      if (engines.canFind("port-audio"))
        dfile.options.merge(DCompilerOptions.PortAudio);

      auto compiled = dfile.compile;
      if (context.errors > 0) return context.errors;

      auto proc = compiled.execute();
      proc.wait();
    } else {
      context.dcode;
      return context.errors;
    }
  }
  return 0;
}
