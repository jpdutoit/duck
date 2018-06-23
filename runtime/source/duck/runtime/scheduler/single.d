module duck.runtime.scheduler.single;

private import duck.runtime;

//private import core.sys.posix.signal : sigset, SIGINT, SIG_DFL;
private import core.stdc.math: floor;
private import core.stdc.stdlib: exit;

version(USE_OSC) {
  import duck.plugin.osc.server;
}

__gshared double now = 0;

struct Scheduler {
  __gshared bool finished = false;
  __gshared ulong sampleIndex = 0;
  __gshared double currentTime = 0;

  /*extern(C)
  static void signalHandler(int value){
    print("Stopping nicely, ctrl-c again to force.");
    finished = true;
    //stdin.close();
    sigset(SIGINT, SIG_DFL);
  }*/

  static void sleep(double dur) nothrow {
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

  extern(C) alias void function() nothrow RunFn;

  static void start(T)(scope T dg) if (is (T:RunFn))
  {
    //sigset(SIGINT, &signalHandler);
    dg();
  }
}

void wait(double dur) nothrow {
  Scheduler.sleep(dur);
}
