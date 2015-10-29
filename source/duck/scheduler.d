module duck.scheduler;

//import std.concurrency : spawn, Tid, send;
private import core.thread : Fiber;
private import std.stdio : write, writeln, stdin, stdout, stderr;
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
    stderr.writeln("Stopping nicely, ctrl-c again to force.");
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
            stderr.write("Fiber ");
            stderr.write(fibers[i].uuid);
            stderr.writeln(" done");
            fibers[i] = null;
          }
        }
      }
      if (activeFibers == 0) return;
      //writefln("nex");
      foreach(UGenInfo *info; UGenRegistry.endPoints.byValue()) {
        /*/writefln("%s", info.connections);*/
        info.tick(sampleIndex);
      }

      //writefln("nex");
      sampleIndex++;

      now.time = now.time + 1.samples;
      //writefln("nex");

/*      auto received =
            receiveTimeout(0.dur!"seconds",
                           (string line) {
                               writefln("Thanks for -->%s<--", line);
                               stdout.flush();
                           });*/
      //if (sampleIndex % 16 == 0)
      //  server.update();
      //writefln("sampleIndex %s", sampleIndex);
      if (sampleIndex % 44100 == 0) {
        stderr.writeln(sampleIndex);
        //std.flush();
        //return;
      }
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

  void opOpAssign(string op: "+")(auto ref Duration other) {
    stderr.write("sleep ");
    stderr.writeln(other.value);
    sleep(other);
  }

  void set() {

  }
}
Now now;
