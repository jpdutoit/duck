module duck.host;

import duck.compiler;
import std.stdio;
import std.process;
import std.algorithm;
import std.array;

private {
  int tmpIndex = 0;
  string tmpFolder = "/tmp/";
}

string temporaryFileName() {
    import std.conv: to;
    return "duck_temp" ~ tmpIndex.to!string;
}

DFile saveToTemporary(DCode code) {
  string filename = tmpFolder ~ temporaryFileName() ~ ".d";
  File dst = File(filename, "w");
  dst.rawWrite(code.code);
  dst.close();
  debug(duck_host) stderr.writefln("Converted to D: %s", filename);
  return DFile(filename);
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

  static immutable DCompilerOptions
    PortAudio = {
      sourceFiles: [
        "deimos/portaudio.di"
      ],
      libraries: ["../runtime/lib/libportaudio.a"],
      frameworks: ["CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"],
      versions: ["USE_PORT_AUDIO"]
    },
    DuckRuntime = {
      flags: ["-release", "-inline"],
      //libraries: ["../bin/libduck.a"],
      sourceFiles: [
        "duck/runtime/package",
        "duck/runtime/model",
        "duck/runtime/scheduler",
        "duck/runtime/entry",
        "duck/runtime/global",
        "duck/stdlib/package",
        "duck/stdlib/scales",
        "duck/stdlib/units",
        "duck/stdlib/ugens",
        "duck/plugin/portaudio/package",
        "duck/plugin/osc/server",
        "duck/plugin/osc/ugen"]
      };
}

struct DFile {
  string filename;

  this(string filename) {
      this.filename = filename;

      this.options.merge(DCompilerOptions.DuckRuntime);
  }

  DCompilerOptions options;

  Executable compile() {
      return compile(tmpFolder ~ temporaryFileName());
  }

  Executable compile(string output) {
    stdout.flush();
    auto command = "dmd " ~ this.filename ~ " -Iruntime/source -of" ~ output ~ buildCommand(options);
    debug(duck_host) stderr.writefln("%s", command);
    Pid compile = spawnShell(command, stdin, stdout, stderr, null, Config.none, null);
    auto result = wait(compile);
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
        command ~= " " ~ path ~ "../runtime/source/" ~ sourceFile;
    foreach (string v; options.versions)
      command ~= " -version=" ~ v;
    foreach(string library; options.libraries)
        command ~= " -L" ~ path ~ library;
    foreach(string framework; options.frameworks)
        command ~= " -L-framework -L" ~ framework;
    return command;
  }
}


struct Executable {
    string filename;

    this(string filename) {
        this.filename = filename;
    }

    Process execute() {
        return Process(this.filename);
    }
}

struct Process {
    string filename;
    Pid pid;

    this(string filename) {
        this.filename = filename;
        this.pid = spawnProcess(this.filename);
    }

    void stop() {
        if (tryWait(pid).terminated)
            return;

        import core.sys.posix.signal : SIGKILL;
        kill(this.pid, SIGKILL);
        .wait(this.pid);

        pid = Pid.init;
    }

    @property bool alive() {
        return !tryWait(pid).terminated;
    }

    void wait() {
      .wait(this.pid);
    }
}
