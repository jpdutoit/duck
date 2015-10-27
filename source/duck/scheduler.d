module duck.scheduler;

//import std.concurrency : spawn, Tid, send;
private import core.thread : Fiber;
private import std.stdio : writefln, stdin, stdout;
//private import duck.server;
private import duck.registry;

private import core.sys.posix.signal;

import duck.units;

class ProcFiber : Fiber
{
  static uint fiberUuid = 0;
  this(scope void delegate() dg) {
    super(dg, 512*1024);
    wakeTime = 0.seconds;
    uuid = ++fiberUuid;
  }
  this(scope void function() fn) {
    super(fn, 512*1024);
    wakeTime = 0.seconds;
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
    writefln("Stopping nicely, ctrl-c again to force.");
    finished = true;
    stdin.close();
    sigset(SIGINT, SIG_DFL);
  }

  static void sleep()
  {
    ProcFiber fiber = cast(ProcFiber)Fiber.getThis(); 
    if (fiber) {
      while (true) {
        Duration waitTime = 1000.0.seconds;
        int alive = 0;
        for (int i = 0; i < fiber.children.length; ++i) {
          if (fiber.children[i].state != Fiber.State.TERM) {
            alive++;
            Duration newWaitTime = fiber.children[i].wakeTime - now;
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

  static void sleep(Duration dur)
  {
    ProcFiber fiber = cast(ProcFiber)Fiber.getThis();
    fiber.wakeTime = fiber.wakeTime + dur;
    //writefln("Fiber %d waiting %s", fiber.uuid, dur);
    Fiber.yield();
  }

  /*static void lineReader(Tid owner)
  {
      import std.string;
      while (!finished && !stdin.eof()) {
          string line = stdin.readln().chomp();
          owner.send(line);
      }
      writefln("Stop listening to input");
      stdout.flush();
  }*/

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
            writefln("Fiber %s done", fibers[i].uuid);
            fibers[i] = null;
          }
        }
      }
      if (activeFibers == 0) return;

      foreach(UGenInfo *info; UGenRegistry.endPoints.byValue()) {
        info.tick(sampleIndex);
      }
      sampleIndex++;

      now.time = now.time + 1.samples;

/*      auto received =
            receiveTimeout(0.dur!"seconds",
                           (string line) {
                               writefln("Thanks for -->%s<--", line);
                               stdout.flush();
                           });*/
      //if (sampleIndex % 16 == 0)
      //  server.update();

      //if (now.time.samples == 44100*100) {
        //writefln("%s", now.time);
        //return;
      //}
    }
    //Scheduler.server.stop();
  }
};

void sleep() {
  Scheduler.sleep();
}

void sleep(Duration dur) {
  Scheduler.sleep(dur);
}

void spork(T)(scope T dg)
{
  Scheduler.start(dg);
}


struct Now {
  Time time = Time.withSamples(0);
  alias time this;

  void opBinaryRight(string op: ">>")(auto ref Duration other) {
    sleep(other);
  }

  void set() {
    
  }
}
Now now;


