module duck.host;

import duck.compiler;
import std.stdio;
import std.process;
import std.algorithm;
import std.array;

//debug = duck_host;


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
      libraries: ["lib/libportaudio.a"],
      frameworks: ["CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"],
      versions: ["USE_PORT_AUDIO"]
    },
    DuckRuntime = {
      flags: ["-release"],
      sourceFiles: [
        "duck/runtime/package",
        "duck/runtime/model",
        "duck/runtime/scheduler",
        "duck/stdlib/package",
        "duck/stdlib/scales",
        "duck/stdlib/units",
        "duck/stdlib/ugens",
        "duck/package",
        "duck/entry",
        "duck/pa",
        "duck/osc",
        "duck/global"]
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
    auto command = "dmd " ~ this.filename ~ " -of" ~ output ~ buildCommand(options);
    debug(duck_host) stderr.writefln("%s", command);
    Pid compile = spawnShell(command, stdin, stdout, stderr, null, Config.none, null);
    auto result = wait(compile);
    debug(duck_host) stderr.writeln("Done compiling");
    return Executable(output);
  }



  //static auto sourceFiles = [


//  static auto libraries  = [];//"lib/libportaudio.a"];//, "source/duck.a"];
//  static auto frameworks = [];//"CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"];
  //static string[] versions = [];
  //static string[] versions   = ["USE_PORT_AUDIO"];

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
        command ~= " " ~ path ~ "source/" ~ sourceFile ~ ".d";
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
        //this.pid = this.pipes.pid;
        //spawn(&streamReader, this.pid.processID(), this.pipes.stderr().getFP());
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

/*
    static void streamReader(int pid, FILE* osFile)
    {
        import std.string;
        File input = File.wrapFile(osFile);
        while (!input.eof()) {
            string line = input.readln().chomp();
            stderr.writefln("[%s] %s", pid, line);
            //owner.send(pid, line);
        }
    }*/

    /*void processStreams() {
        writefln("ff");
        //static ubyte[8192] buffer;
        if (!pipes.stderr.eof()) {
            foreach(s; pipes.stderr.byLine)
                stderr.writefln("[%s] %s", this.pid.processID(), s);
            //stdin.byLine.copy(stderr.lockingTextWriter());
        }
    }
*/
    //ProcessPipes pipes;
}
