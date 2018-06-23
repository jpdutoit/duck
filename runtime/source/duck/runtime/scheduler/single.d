module duck.runtime.scheduler.single;

private import duck.runtime;

//private import core.sys.posix.signal : sigset, SIGINT, SIG_DFL;
private import core.stdc.math: floor;
private import core.stdc.stdlib: exit;

version(USE_OSC) {
  import duck.plugin.osc.server;
}

struct Scheduler {
  static bool finished = false;
  static ulong sampleIndex = 0;
  static double currentTime = 0;

  /*extern(C)
  static void signalHandler(int value){
    print("Stopping nicely, ctrl-c again to force.");
    finished = true;
    //stdin.close();
    sigset(SIGINT, SIG_DFL);
  }*/

  static void sleep(double dur) {
    currentTime += dur;
    ulong targetTime = cast(ulong)floor(currentTime);

    while (sampleIndex < targetTime) {
      version(USE_INSTRUMENTATION) {
        import duck.stdlib : instrumentNextSample;
        instrumentNextSample();
      }

      now += 1;
      sampleIndex++;
      _idx = sampleIndex;

      foreach(ugenTick; UGenRegistry.endPoints.byValue()) {
        ugenTick();
      }

      if (finished) exit(0);

      version(USE_OSC) {
        if (sampleIndex % 32 == 0)
          oscServer.receiveAll();
      }
    }

  }

  static void start(T)(scope T dg) if (is (T:void delegate()) || is (T:void function()))
  {
    //sigset(SIGINT, &signalHandler);
    dg();
  }

  static void run() { }
}

void wait(double dur) {
  Scheduler.sleep(dur);
}

double now = 0;
