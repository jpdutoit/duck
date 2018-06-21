module duck.runtime.scheduler;

private import core.thread : Fiber;
private import duck.runtime;

private import core.sys.posix.signal : sigset, SIGINT, SIG_DFL;
version(USE_OSC) {
  import duck.plugin.osc.server;
}

import duck.stdlib.units;

class ProcFiber : Fiber
{
  static uint fiberUuid = 0;
  this(scope void delegate() dg) {
    super(dg, 512*1024);
    wakeTime = 0;
    uuid = ++fiberUuid;
  }
  this(scope void function() fn) {
    super(fn, 512*1024);
    wakeTime = 0;
    uuid = ++fiberUuid;
  }
  uint uuid;
  Time wakeTime;
  ProcFiber[] children;
};



struct Scheduler {
  //static Server server;

  static bool finished = false;
  static uint activeFibers = 0;
  static ProcFiber[] fibers;

  extern(C)
  static void signalHandler(int value){
    print("Stopping nicely, ctrl-c again to force.");
    finished = true;
    //stdin.close();
    sigset(SIGINT, SIG_DFL);
  }

  static void sleep()
  {
    ProcFiber fiber = cast(ProcFiber)Fiber.getThis();
    if (fiber) {
      while (true) {
        duration waitTime = 1000.0 * SAMPLE_RATE;
        int alive = 0;
        for (int i = 0; i < fiber.children.length; ++i) {
          if (fiber.children[i].state != Fiber.State.TERM) {
            alive++;
            duration newWaitTime = fiber.children[i].wakeTime - now;
            if (newWaitTime < waitTime)
              waitTime = newWaitTime;
          }
        }
        if (alive > 0) {
          waitTime >> now;
          //wait(waitTime);
        }
        else
          return;
      }
    }
  }

  static void sleep(duration dur)
  {
    ProcFiber fiber = cast(ProcFiber)Fiber.getThis();
    fiber.wakeTime = fiber.wakeTime + dur;
    //writefln("Fiber %d waiting %s", fiber.uuid, dur);
    Fiber.yield();
  }

  static void start(T)(scope T dg)
    if (is (T:void delegate()) || is (T:void function()))
  {
    ProcFiber parent = cast(ProcFiber)Fiber.getThis();

    ProcFiber fiber = new ProcFiber( dg );
    fiber.wakeTime = now.time;
    fiber.call();

    if (fiber.state != Fiber.State.TERM) {
      if (parent) {
        parent.children ~= fiber;
      }
      activeFibers++;
      fibers ~= fiber;
    }
  }

  static void tick(ref ulong sampleIndex) {
    now.time = now.time + 1;
    sampleIndex++;

    _idx = sampleIndex;
    //print("__idx ", __idx, "\n");
    foreach(ugenTick; UGenRegistry.endPoints.byValue()) {
      ugenTick();
    }
  }

  static void run() {
    //spawn(&lineReader, thisTid);
    sigset(SIGINT, &signalHandler);
    //Scheduler.server.start(4000);
    ulong sampleIndex = 0;

    while (!finished) {
      //writefln("Sample %d", sampleIndex); stdout.flush();
      bool first = true;
      for (int i = 0; i < fibers.length; ++i) {
        if (fibers[i] && now >= fibers[i].wakeTime) {
          if (first) {
            first = false;
          }
          fibers[i].call();
          if (fibers[i].state == Fiber.State.TERM) {
            activeFibers--;
            debug print("Fiber ", fibers[i].uuid, " done");
            //stderr.write("Fiber ");
            //stderr.write(fibers[i].uuid);
            //stderr.writeln(" done");
            fibers[i] = null;
          }
        }
      }
      if (activeFibers == 0) return;

      version(USE_INSTRUMENTATION) {
        import duck.stdlib : instrumentNextSample;
        instrumentNextSample();
      }
      tick(sampleIndex);

      //writefln("sampleIndex %s", sampleIndex);
      version(USE_OSC) {
        if (sampleIndex % 32 == 0)
          oscServer.receiveAll();
      }
      if (sampleIndex % 44100 == 0) {
        //print(sampleIndex);
        //print("\n");
        //return;
      }
    }
    //Scheduler.server.stop();
  }
};

void sleep(duration dur) {
  Scheduler.sleep(dur);
}

void wait(duration dur) {
  Scheduler.sleep(dur);
}

struct Now {
  Time time = 0;
  alias time this;

  void opBinaryRight(string op: ">>")(auto ref duration other) {
    sleep(other);
  }

  void opOpAssign(string op: "+")(auto ref duration other) {
    /*print("sleep ");
    print(other.value);
    print("\n");*/
    sleep(other);
  }

  void set() {

  }
}
Now now;
