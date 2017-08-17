module duck.host;

import duck.compiler;
import std.process: spawnProcess, tryWait, kill, wait, Pid;
import std.path : buildPath;

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
