module interactive_host;

import duck.compiler, duck.host;

import std.file, std.stdio, std.path, std.algorithm, std.array, core.thread, std.process, std.concurrency;
import core.sys.posix.signal;

Process[] procList;

void log(T...)(T t) {
  stderr.writefln(t);
  stderr.flush();
}

extern(C)
static void signalHandler(int value) {
    sigset(SIGINT, SIG_DFL);

    foreach(ref Process process; procList)
        process.stop();
    //writefln("Intercepted");
    //kill(process, SIGKILL);
}

void waitForProcesses() {
    sigset(SIGINT, &signalHandler);

outerLoop:
    while(true) {
        Thread.sleep(100.msecs);
        foreach(ref Process process; procList) {
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
      auto ast = SourceBuffer(filename).parse();
      auto dcode = ast.codeGen();
      return dcode.saveToTemporary();
    }
}

struct Command {
    string name;
    string[] args;
};

Command parseCommand(string s) {
    import std.regex;
    auto r = regex(`\s*([^\s]+|"[^"]*")\s*`);
    Command command;
    int index = 0;
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
                      dFile.options.merge(DCompilerOptions.PortAudio);
                      auto process = dFile.compile().execute();
                      procList ~= process;
                      writefln("%s,%s", process.pid.processID(), process.filename);
                      stdout.flush();
                    } else {
                      writefln("");
                      stdout.flush();
                    }
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
        }
    }
}


int main(string[] args) {
  interactiveMode();
  return 0;
}
