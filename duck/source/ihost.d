module interactive_host;

import std.stdio;

import duck;
import duck.compiler;
import duck.compiler.backend.d;

Process[] procList;

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
    import std.algorithm: filter;
    import std.array: array;
    list = list.filter!(a => a.alive)().array;

    foreach(i, ref process; list) {
        auto id = process.pid.processID();
        if (id >= 0)
            process.describe();
    }
}

void interactiveMode() {
    auto root = Context.createRootContext();
    while(true) {
        write(">");
        stdout.flush();
        auto s = std.stdio.readln();
        auto cmd = parseCommand(s[0..$-1]);
        //writefln("Command %s", cmd);
        if (cmd.name) {
            if (cmd.name == "help") {
                writeln(q"[
Commands:
  list             - List all active modules
  stop id          - Stop the module with the given id
  start filename   - Start a module
]");
            }
            else if (cmd.name == "start") {
                foreach (filename; cmd.args) {
                    Context context = root.createFileContext(filename);

                    context.library;
                    if (context.hasErrors) continue;

                    Backend backend = new DBackend(context);

                    if (auto compiler = backend.compiler) {
                      auto compiled = compiler.compile(["port-audio"]);

                      if (context.hasErrors) continue;

                      auto process = compiled.execute();
                      process.describe();
                      procList ~= process;
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
