module host;

import std.file, std.stdio, std.path, std.algorithm, std.array, core.thread, std.process, duck.parse, std.concurrency;

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
  writefln(t);
  stdout.flush();
}

import core.sys.posix.signal;

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

    DFile convertToD() {
        return convertToD(tmpFolder ~ temporaryFileName() ~ ".d");
    }

    DFile convertToD(string output) {
         char buffer[1024*1024];

        // Read input file
        File src = File(this.filename, "r");
        auto buf = src.rawRead(buffer);
        src.close();

        // Save converted intermediate file
        log("Converting to D");
        auto s = .compile(buf);
        File dst = File(output, "w");
        dst.rawWrite(s);
        dst.close();
        log("Converted to D");
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
        log("Compiling");
        stdout.flush();
        auto command = "dmd " ~ this.filename ~ " -debug -of" ~ output ~ buildCommand(sourceFiles, libraries, frameworks);
        log("%s", command);
        Pid compile = spawnShell(command, stdin, stdout, stdout, null, Config.none, null);
        auto result = .wait(compile);
        log("Done compiling");
        return Executable(output);
    }

    void check() {
        auto command = "dmd -c -o- " ~ this.filename ~ buildCommand();
        //writefln("command: %s", command);
        Pid compile = spawnShell(command, stdin, stdout, stdout, null, Config.none, null);
        auto result = .wait(compile);
    }


    static auto sourceFiles = [
      "duck/runtime/package", "duck/runtime/model",
        "duck/runtime/registry", "duck/runtime/scheduler", "duck/runtime/types",

      "duck/stdlib/package", "duck/stdlib/scales",
        "duck/stdlib/units", "duck/stdlib/ugens",
      "duck/package", "duck/entry", "duck/pa",
      "duck/global"];
    static auto libraries  = ["lib/libportaudio.a"];//, "source/duck.a"];
    static auto frameworks = ["CoreAudio", "CoreFoundation", "CoreServices", "AudioUnit", "AudioToolbox"];

    static string buildCommand(string[] sourceFiles = null, string[] libraries = null, string[] frameworks = null) {
        string command = " -I" ~ path ~ "source -inline -version=NO_PORT_AUDIO -release -I" ~ path;
        foreach(string sourceFile; sourceFiles)
            command ~= " " ~ path ~ "source/" ~ sourceFile ~ ".d";
        //foreach(string library; libraries)
        //    command ~= " -L" ~ path ~ library;
        //foreach(string framework; frameworks)
        //    command ~= " -L-framework -L" ~ framework;
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
        spawn(&streamReader, this.pid.processID(), this.pipes.stdout().getFP());
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
        if (cmd.name) {
            if (cmd.name == "start") {
                foreach (filename; cmd.args) {
                    auto process = DuckFile(filename).convertToD().compile().execute();
                    //auto process = Process(filename, false);
                    //process.start();
                    procList ~= process;
                    writefln("%s,%s", process.pid.processID(), process.filename);
                    stdout.flush();
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
                        writefln("send to %s '%s'", pid, cmd.args[1..$].join(" "));
                        process.pipes.stdin().writefln(cmd.args[1..$].join(" "));
                        process.pipes.stdin().flush();
                    }
                }
            }
        }
    }
}

void main(string[] args) {
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
    log("Start");
    if (args.length > 1) {
        string command = args[1];

        if (command == "nothing") {
          return;
        }
        if (command == "check") {
            string target = args[2];
            DuckFile(target).convertToD;
            return;
        }
        else if (command == "build") {
            string target = args[2];
            DuckFile(target).convertToD.compile(target.stripExtension());
        }
        else if (command == "run") {
            string target = args[2];
            procList ~= DuckFile(target).convertToD.compile.execute;
            waitForProcesses();
            return;
        }
        else writeHelp();
    } else {
        interactiveMode();
    }
}
