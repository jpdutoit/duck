module duck.compiler.backend.d.dmd;
import duck.compiler.backend.backend: Executable;
import duck.compiler.context: Context;
import std.algorithm: canFind;
import std.exception: assumeUnique;
import std.stdio: stdout, stdin, stderr;
import std.process;
import std.path : buildPath;

private {
  string tmpFolder = "/tmp/";
}

struct DCompilerOptions {
  string[] flags;
  string[] sourceFiles;
  string[] libraries;
  string[] frameworks;
  string[] versions;

  void merge(const DCompilerOptions options) {
    foreach (s; options.flags)
      if (!flags.canFind(s)) flags ~= s;
    foreach (s; options.sourceFiles)
      if (!sourceFiles.canFind(s)) sourceFiles ~= s;
    foreach (s; options.libraries)
      if (!libraries.canFind(s)) libraries ~= s;
    foreach (s; options.frameworks)
      if (!frameworks.canFind(s)) frameworks ~= s;
    foreach (s; options.versions)
      if (!versions.canFind(s)) versions ~= s;
  }

  version(OSX)
  static immutable DCompilerOptions PortAudio = {
    sourceFiles: [
      "duck/plugin/portaudio/package",
      "deimos/portaudio.di"
    ],
    libraries: ["libportaudio.a"],
    frameworks: ["CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"],
    versions: ["USE_PORT_AUDIO"]
  };

  static immutable DCompilerOptions
    OSC = {
      versions: ["USE_OSC"],
      sourceFiles: [
        "duck/plugin/osc/server",
        "duck/plugin/osc/ugen"
      ]
    },
    Instrumentation = {
      sourceFiles: [
        "duck/runtime/instrument.d"
      ],
      versions: ["USE_INSTRUMENTATION"]
    },
    DuckRuntime = {
      flags: ["-release", "-inline", "-L-dead_strip"],
      //libraries: ["../bin/libduck.a"],
      sourceFiles: [
        "duck/runtime/package",
        "duck/runtime/model",
        "duck/runtime/scheduler/single",
        "duck/runtime/entry",
        "duck/runtime/global",
        "duck/runtime/print",
        "duck/stdlib/package",
        "duck/stdlib/scales",
        "duck/stdlib/units",
        "duck/stdlib/ugens",
        "duck/stdlib/random"
      ]
      };
}

struct DFile {
  Context context = null;
  string filename;
  string name;
  DCompilerOptions options;

  bool opCast() {
    return filename != null;
  }

  this(string filename, string name = null) {
    this.name = name;
    this.filename = filename;
    this.options.merge(DCompilerOptions.DuckRuntime);
    this.options.sourceFiles ~= this.filename;
  }

  void write(string code) {
    import std.stdio: File;
    File dst = File(this.filename, "w");
    dst.rawWrite(code);
    dst.close();
  }

  static tempFromHash(size_t hash) {
    import std.digest : toHexString;
    ubyte[8] result = (cast(ubyte*) &hash)[0..8];
    string name = "_duck_" ~ toHexString(result[0..8]).assumeUnique;
    string filename = (tmpFolder ~ name ~ ".d").assumeUnique;
    return DFile(filename, name);
  }

  Executable compile() {
      return compile(tmpFolder ~ name ~ ".bin");
  }

  Executable compile(string output) {
    stdout.flush();
    auto command = "dmd -of=" ~ output ~ buildCommand(options);
    if (context.verbose) stderr.writeln("EXECUTE: ", command);
    debug(duck_host) stderr.writefln("%s", command);
    Pid compile = spawnShell(command, stdin, stdout, stderr, null, Config.none, null);
    auto result = wait(compile);
    if (result != 0) {
      debug(duck_host) stderr.writeln("Error compiling: ", result);
      return Executable("");
    }
    debug(duck_host) stderr.writeln("Done compiling");
    return Executable(output);
  }

  static string hostFolder() {
    import core.runtime;
    import std.path : dirName;
    string path = dirName(Runtime.args[0]);
    if (path.length > 0 && (path[$-1] != '/' && path[$-1] != '\\'))
        path = path ~ "/";
    return path;
  }

  static string buildCommand(DCompilerOptions options) {
    string path = hostFolder;
    string command;
    foreach (string v; options.flags)
      command ~= " " ~ v;
    foreach(string sourceFile; options.sourceFiles)
      command ~= " " ~ buildPath(hostFolder, "../runtime/source/", sourceFile);
    foreach (string v; options.versions)
      command ~= " -version=" ~ v;
    foreach(string library; options.libraries)
        command ~= " -L" ~ buildPath(hostFolder, "../runtime/lib", library);
    foreach(string framework; options.frameworks)
        command ~= " -L-framework -L" ~ framework;
    return command;
  }
}
