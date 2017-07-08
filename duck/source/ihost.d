module interactive_host;

import duck.compiler, duck.host;

import duck;
import duck.compiler.context;

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
/*
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
}*/

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

void describe(Process process) {
    writeln(process.pid.processID(), ": ", process.filename);
}

void describe(ref Process[] list) {
    list = list.filter!(a => a.alive)().array;

    foreach(i, ref process; list) {
        auto id = process.pid.processID();
        if (id >= 0)
            process.describe();
    }
}

void interactiveMode() {
    while(true) {
        write(">");
        stdout.flush();
        auto s = std.stdio.readln();
        auto cmd = parseCommand(s[0..$-1]);
        //writefln("Command %s", cmd);
        if (cmd.name) {
            if (cmd.name == "help") {
                writeln("""Commands:
  list             - List all active modules
  stop id          - Stop the module with the given id
  start filename   - Start a module
""");
            }
            else if (cmd.name == "start") {
                foreach (filename; cmd.args) {
                    Context context = Duck.contextForFile(filename);

                    if (context.hasErrors) continue;

                    context.library;

                    if (context.hasErrors) continue;

                    DFile dfile = context.dfile;

                    if (context.hasErrors) continue;

                    if (true)
                        dfile.options.merge(DCompilerOptions.PortAudio);

                    auto process = dfile.compile.execute();
                    process.describe();
                    procList ~= process;
                    stdout.flush();
                }
            }
            else if (cmd.name == "stop") {
                import std.conv: to;
                foreach (pidString; cmd.args) {
                    int pid = pidString.to!int;
                    foreach(process; procList) {
                        if (process.pid.processID() == pid) {
                          process.describe();
                            process.stop();
                        }
                    }
                }
                stdout.flush();
            }
            else if (cmd.name == "list") {
                procList.describe();
                stdout.flush();
            }
            else if (cmd.name == "quit") {
                return;
            }
            else {
                writeln("Unknown command: ", cmd.name);
            }
        }
    }
}


int main(string[] args) {
  interactiveMode();
  return 0;
}
