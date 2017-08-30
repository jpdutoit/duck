module duck.compiler.backend.backend;

import std.stdio : File;
import std.process: spawnProcess, tryWait, kill, wait, Pid;

import duck.compiler.context : Context;

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

struct SourceFile {
  string filename;
  string sourceCode;

  void save() {
    File dst = File(filename, "w");
    dst.rawWrite(sourceCode);
    dst.close();
  }
}

interface SourceToSourceCompiler {
  SourceFile[] transpile();
}

interface SourceToBinaryCompiler {
  Executable compile(string[] engines = []);
}

abstract class Backend {
  Context context;

  this(Context context) {
    this.context = context;
  }

  SourceToBinaryCompiler compiler() {
    return cast(SourceToBinaryCompiler)this;
  }

  SourceToSourceCompiler transpiler() {
    return cast(SourceToSourceCompiler)this;
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

    bool opCast(){
      return filename != null && filename.length > 0;
    }

    void move(string target) {
      import std.path: buildPath;
      import std.file: copy, remove, PreserveAttributes;
      target = buildPath(".", target);
      copy(this.filename, target, PreserveAttributes.yes);
      remove(this.filename);
      this.filename = target;
    }
}
