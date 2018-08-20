module duck.runtime.entry;
import duck.runtime;
import duck.stdlib;
import duck.stdlib.ugens : bigEndian;
import duck.stdlib.random;

version(USE_OSC) {
  import duck.plugin.osc.server;
}

void initialize(char*[] args) nothrow {
  import core.stdc.string: strcmp, strlen;
  import core.stdc.stdlib: atoi;

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
    if (strcmp(args[i], "--output") == 0) {
      auto mode = args[++i];
      if (strcmp(mode, "au") == 0)
        outputMode = OutputMode.AU;
      else if (strcmp(mode, "pa") == 0)
        outputMode = OutputMode.PortAudio;
      else {
        print("Unknown output mode: ");
        print(mode);
        halt();
      }

    }
    else if (strcmp(args[i], "--sample-rate") == 0) {
      SAMPLE_RATE = atoi(args[++i]);
    }
    else if (strcmp(args[i], "--verbose") == 0 || strcmp(args[i], "-v") == 0) {
      verbose = true;
    }
    else {
      print("Unexpected argument: ");
      print(args[i]);
      halt();
    }
  }

  if (outputMode == OutputMode.AU) {
    static header = [cast(uint)24.bigEndian, 0xffffffff, 6.bigEndian, 0, 2.bigEndian];
    header[3] = (cast(uint)SAMPLE_RATE).bigEndian;
    rawWrite2(".snd");
    rawWrite2(header);
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
  //Workaround for module constructors not getting called anymore for unknown reasons
  randomGenerator = Xoroshiro128.withCurrentTime();
  Scheduler.start(&run);
  rt_term();
}
