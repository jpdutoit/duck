module host;

import std.file, std.stdio, std.path, std.algorithm, std.array, core.thread, std.process, duck.parse, std.concurrency;
import core.sys.posix.signal;
string path;

Proc[] procList;

void writeHelp() {
    writefln(q"TXT
duck

Commands:
  build duck_file
  check duck_file
  run duck_file

TXT");
}

void log(T...)(T t) {
  stderr.writefln(t);
  stderr.flush();
}

version(DUCK_TEST_SUITE) {} else {

extern(C)
static void signalHandler(int value) {
    sigset(SIGINT, SIG_DFL);

    foreach(ref Proc process; procList)
        process.stop();
    //writefln("Intercepted");
    //kill(process, SIGKILL);
}

void waitForProcesses() {
    sigset(SIGINT, &signalHandler);

outerLoop:
    while(true) {
        Thread.sleep(100.msecs);
        foreach(ref Proc process; procList) {
            auto result = tryWait(process.pid);
            if (!result.terminated) continue outerLoop;
        }
        break;
    }
}

}

int tmpIndex = 0;
string tmpFolder = "/tmp/";

string temporaryFileName() {
    import std.conv: to;
    return "duck_temp" ~ tmpIndex.to!string;
}


struct DuckFile {
    string filename;

    this(string filename) {
        this.filename = filename;
    }

    int check() {
      int a = checkit(filename);
      return a;
      /*char buffer[1024*1024];

     // Read input file
     File src = File(this.filename, "r");
     auto buf = src.rawRead(buffer);
     src.close();

     // Save converted intermediate file
     debug log("Converting to D");
     .check(buf);*/

    }

    DFile convertToD() {
        return convertToD(tmpFolder ~ temporaryFileName() ~ ".d");
    }

    DFile convertToD(string output) {
         /*char buffer[1024*1024];

        // Read input file
        File src = File(this.filename, "r");
        auto buf = src.rawRead(buffer);
        src.close();
*/
        // Save converted intermediate file
        debug log("Converting to D");
        auto s = .compile(filename);
        if (!s || !s.length ) return DFile(null);

        File dst = File(output, "w");
        dst.rawWrite(s);
        dst.close();
        debug log("Converted to D");
        return DFile(output);
    }
}

struct DFile {
    string filename;

    this(string filename) {
        this.filename = filename;
    }

    Executable compile() {
        return compile(tmpFolder ~ temporaryFileName());
    }

    Executable compile(string output) {
        debug log("Compiling");
        stdout.flush();
        auto command = "dmd " ~ this.filename ~ " -of" ~ output ~ buildCommand(sourceFiles, libraries, frameworks);
        log("%s", command);
        Pid compile = spawnShell(command, stdin, stdout, stdout, null, Config.none, null);
        auto result = .wait(compile);
        log("Done compiling");
        return Executable(output);
    }

    int check() {
        auto command = "dmd -c -o- " ~ this.filename ~ buildCommand();
        //writefln("command: %s", command);
        Pid compile = spawnShell(command, stdin, stdout, stderr, null, Config.none, null);
        auto result = .wait(compile);
        return result;
    }


    static auto sourceFiles = [
      "duck/runtime/package", "duck/runtime/model",
        "duck/runtime/scheduler",
      "duck/stdlib/package", "duck/stdlib/scales",
        "duck/stdlib/units", "duck/stdlib/ugens",
      "duck/package", "duck/entry", "duck/pa", "duck/osc",
      "duck/global"];
    static auto libraries  = ["lib/libportaudio.a"];//, "source/duck.a"];
    static auto frameworks = ["CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"];
    //static string[] versions = [];
    static string[] versions   = ["USE_PORT_AUDIO"];

    static string buildCommand(string[] sourceFiles = null, string[] libraries = null, string[] frameworks = null) {
        string command = " -I" ~ path ~ "source -release -I" ~ path;
        foreach(string sourceFile; sourceFiles)
            command ~= " " ~ path ~ "source/" ~ sourceFile ~ ".d";

        foreach (string v; versions)
          command ~= " -version=" ~ v;
        foreach(string library; libraries)
            command ~= " -L" ~ path ~ library;
        foreach(string framework; frameworks)
            command ~= " -L-framework -L" ~ framework;
        return command;
    }
}

struct Executable {
    string filename;

    this(string filename) {
        this.filename = filename;
    }

    Proc execute() {
        return Proc(this.filename);
    }
}

struct Proc {
    string filename;
    Pid pid;

    this(string filename) {
        this.filename = filename;
        this.pipes = pipeProcess(this.filename);
        this.pid = this.pipes.pid;
        spawn(&streamReader, this.pid.processID(), this.pipes.stderr().getFP());
    }

    void stop() {
        if (tryWait(pid).terminated)
            return;

        kill(this.pid, SIGKILL);
        wait(this.pid);

        pid = Pid.init;
    }

    @property bool alive() {
        return !tryWait(pid).terminated;
    }

    static void streamReader(int pid, FILE* osFile)
    {
        import std.string;
        File input = File.wrapFile(osFile);
        while (!input.eof()) {
            string line = input.readln().chomp();
            stderr.writefln("[%s] %s", pid, line);
            //owner.send(pid, line);
        }
    }

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
    ProcessPipes pipes;
}

version(DUCK_TEST_SUITE) {} else {

struct Command {
    string name;
    string[] args;
};

Command parseCommand(string s) {
    import std.regex;
    auto r = regex(`\s*([^\s]+|"[^"]*")\s*`);
    Command command;
    int index = 0;;
    foreach(c; s.matchAll(r)) {
        if (index++ == 0) {
            command.name = c[1];
        }
        else
            command.args ~= c[1];

    }
    //writefln("%s %s", command, command.args.length);
    return command;
}

void interactiveMode() {
    while(true) {
        /*if (stdin.eof()) {
            foreach(c; processList) {
                c.processStreams();
            }
            continue;
        }*/
        auto s = std.stdio.readln();
        auto cmd = parseCommand(s[0..$-1]);
        //writefln("Command %s", cmd);
        if (cmd.name) {
            if (cmd.name == "start") {
                foreach (filename; cmd.args) {
                    auto dFile = DuckFile(filename).convertToD;
                    if (dFile.filename) {
                      auto process = dFile.compile().execute();
                      procList ~= process;
                      writefln("%s,%s", process.pid.processID(), process.filename);
                      stdout.flush();
                    } else {
                      writefln("");
                      stdout.flush();
                    }
                    //auto process = Process(filename, false);
                    //process.start();
                }
            }
            else if (cmd.name == "stop") {
                import std.conv: to;
                foreach (pidString; cmd.args) {
                    int pid = pidString.to!int;
                    foreach(process; procList) {
                        if (process.pid.processID() == pid) {
                            writefln("%s,%s", process.pid.processID(), process.filename);
                            stdout.flush();
                            process.stop();
                        }
                    }
                }

                procList = procList.filter!(a => a.alive)().array;
            }
            else if (cmd.name == "list") {
                procList = procList.filter!(a => a.alive)().array;
                foreach(i, ref c; procList) {
                    auto id = c.pid.processID();
                    if (id >= 0)
                        writef("%s,%s", id, c.filename);
                    if (i + 1 < procList.length)
                        writef(";");
                }
                writefln("");
                stdout.flush();
            }
            else if (cmd.name == "send" && cmd.args.length > 1) {
                import std.conv: to;
                int pid = cmd.args[0].to!int;
                foreach(process; procList) {
                    if (process.pid.processID() == pid) {
                        //writefln("send to %s '%s'", pid, cmd.args[1..$].join(" "));
                        process.pipes.stdin().writefln(cmd.args[1..$].join(" "));
                        process.pipes.stdin().flush();
                    }
                }
            }
        }
    }
}

}
version (D_Coverage) {
  extern (C) void dmd_coverDestPath(string);
  extern (C) void dmd_coverSourcePath(string);
  extern (C) void dmd_coverSetMerge(bool);
}
int main(string[] args) {
  version(DUCK_TEST_SUITE) {
    version(D_Coverage) {
      dmd_coverSourcePath("../");
      dmd_coverDestPath("coverage");
      dmd_coverSetMerge(true);
    }
  }
    version(unittest) {
        log("Unittests passed.");
        return;
    }
    import std.path : dirName;
    path = dirName(args[0]);
    if (path.length > 0 && (path[$-1] != '/' && path[$-1] != '\\'))
        path = path ~ "/";

    //writefln("%s %s", args, path);
    /*if (args.length args.length < 2) {
        writeHelp();
        return;
    }*/
    //log("Start");
    if (args.length > 1) {
        string command = args[1];

        if (command == "nothing") {
          return 0;
        }
        if (command == "check") {
            string target = args[2];
            auto result = DuckFile(target).check;
            stderr.close();
            return result;
        }
        else if (command == "build") {
            string target = args[2];
            auto dFile = DuckFile(target).convertToD;
            if (dFile.filename)
              dFile.compile(target.stripExtension());
        }
        else if (command == "run") {
          version(DUCK_TEST_SUITE) {} else {
            string target = args[2];
            auto dFile = DuckFile(target).convertToD;
            if (dFile.filename) {
              auto executable = dFile.compile();
              procList ~= executable.execute;
              waitForProcesses();
            }
            return 0;
          }
        }
        else writeHelp();
    } else {
      version(DUCK_TEST_SUITE) {} else {
        interactiveMode();
      }
    }
    return 0;
}
