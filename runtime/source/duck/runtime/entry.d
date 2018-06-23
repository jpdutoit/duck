module duck.runtime.entry;
import duck.runtime;
import duck.stdlib;
import duck.stdlib.ugens : bigEndian;

version(USE_OSC) {
  import duck.plugin.osc.server;
}

void initialize(char*[] args) nothrow {
  version(USE_OSC) {
    oscServer = OSCServer();
    oscServer.start(8000);
  }

  version(USE_PORT_AUDIO) {
    outputMode = OutputMode.PortAudio;
  }
  else {
    outputMode = OutputMode.None;
  }

  for (int i = 1; i < args.length; ++i) {
    if (args[i] == "--output") {
      auto mode = args[++i];
      if (mode == "au")
        outputMode = OutputMode.AU;
      else if (mode == "pa")
        outputMode = OutputMode.PortAudio;
      else {
        print("Unknown output mode: ");
        print(mode);
        halt();
      }

    }
    else if (args[i] == "--sample-rate") {
      //FIXME: Parse sample rate
      //SAMPLE_RATE = hz(args[++i].to!int());
    }
    else if (args[i] == "--verbose" || args[i] == "-v") {
      verbose = true;
    }
    else {
      print("Unexpected argument: ");
      print(args[i]);
      halt();
    }
  }

  if (outputMode == OutputMode.AU) {
    rawWrite2(".snd");
    rawWrite2([cast(uint)24.bigEndian, 0xffffffff, 6.bigEndian, (cast(uint)SAMPLE_RATE).bigEndian, 2.bigEndian]);
  }
  else if (outputMode ==  OutputMode.PortAudio) {
    version(USE_PORT_AUDIO) {
      audio.init();
    } else {
      halt("PortAudio support not compiled in.");
    }
  }
  /*
  print("Sample rate: ");
  print(SAMPLE_RATE.value);
  print("\n");
  */
}

import core.memory: GC;

extern(C) void run() nothrow;
extern(C) int rt_init();
extern(C) int rt_term();

extern(C) void main(int argc, char **argv)
{

  initialize(argv[0..argc]);
  rt_init();
  Scheduler.start(&run);
  rt_term();
}
