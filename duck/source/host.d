module host;

immutable VERSION = import("VERSION");

import duck.compiler;
import duck.host;
import std.file : getcwd;
import std.path : buildPath, dirName;
import std.stdio;
import std.format: format;
import std.algorithm.searching;
import duck.compiler.context;
import std.getopt, std.array;
import core.stdc.stdlib : exit;

import duck;

immutable TARGET_CHECK        = "check";
immutable TARGET_EXECUTABLE   = "exe";
immutable TARGET_JSON         = "json";
immutable TARGET_RUN          = "run";
immutable TARGETS = [TARGET_CHECK, TARGET_RUN, TARGET_EXECUTABLE, TARGET_JSON];
immutable TARGETS_DEFAULT = TARGET_RUN;

immutable ENGINE_NULL         = "null";
immutable ENGINE_PORT_AUDIO   = "port-audio";
immutable ENGINES = [ENGINE_PORT_AUDIO, ENGINE_NULL];
immutable ENGINES_DEFAULT = ENGINE_PORT_AUDIO;

version (D_Coverage) {
  extern (C) void dmd_coverDestPath(string);
  extern (C) void dmd_coverSourcePath(string);
  extern (C) void dmd_coverSetMerge(bool);
}

void printHelp(GetoptResult result, string error = null) {
  defaultGetoptPrinter(
    "Duck " ~ VERSION ~ "\n"
    "Usage:\n"
    "  duck { options } input.duck\n"
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
    //bool forever = false;
    bool noStdLib = false;
    string outputName = "output";
    string[] engines = [];
    string[] targets = [];

    auto result = getopt(
      args,
      std.getopt.config.bundling,
      std.getopt.config.keepEndOfOptions,
      "target|t", format("Targets: %-(%s, %)  (defaults to %s)", TARGETS, TARGETS_DEFAULT), &targets,
      "output|o", "Output filename (excluding extension)", &outputName,
      "engine|e", format("Audio engines: %-(%s, %)  (defaults to %s)", ENGINES, ENGINES_DEFAULT), &engines,
      "nostdlib|n", "Do not automatically import the standard library", &noStdLib,
      //"forever|f", "Run forever", &forever,
      "verbose|v", "Verbose output", &verbose
    );

    // Set default audio engines, and target
    if (engines.length == 0) engines = [ENGINES_DEFAULT];
    if (targets.length == 0) targets = [TARGETS_DEFAULT];

    if (result.helpWanted || args.length == 1) {
      printHelp(result);
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

    if (targets.canFind(TARGET_JSON)) {
      import duck.compiler.visitors.json;
      auto json = context.generateJson();
      if (outputName == "-") {
        stdout.writeln(json);
      } else {
        import std.file;
        write(outputName ~ ".json", json);
      }
    }

    if (context.errors == 0
    && (targets.canFind(TARGET_RUN) || targets.canFind(TARGET_EXECUTABLE))) {
      context.dcode;

      auto dfile = context.dfile();
      if (context.errors > 0) return context.errors;

      if (engines.canFind(ENGINE_PORT_AUDIO))
        dfile.options.merge(DCompilerOptions.PortAudio);

      auto compiled = dfile.compile;
      if (context.errors > 0) return context.errors;

      if (targets.canFind(TARGET_EXECUTABLE) && outputName != "-") {
        import std.file;
        copy(compiled.filename, outputName);
      }

      if (targets.canFind(TARGET_RUN)) {
        auto proc = compiled.execute();
        proc.wait();
      }
    }

    return context.errors;
  }
}
