module duck.runtime.entry;
import duck.runtime;
import duck.stdlib;
import duck.stdlib.ugens : bigEndian;

version(USE_OSC) {
  import duck.plugin.osc.server;
}

void initialize(string[] args) {
  version(USE_OSC) {
    oscServer = new OSCServer();
    oscServer.start(8000);
  }

  version(USE_PORT_AUDIO) {
    outputMode = OutputMode.PortAudio;
  }
  else {
    outputMode = OutputMode.AU;
  }

  for (int i = 1; i < args.length; ++i) {
    if (args[i] == "--output") {
      string mode = args[++i];
      if (mode == "au")
        outputMode = OutputMode.AU;
      else if (mode == "pa")
        outputMode = OutputMode.PortAudio;
      else
        halt("Unknown output mode: " ~ mode);
    }
    else if (args[i] == "--sample-rate") {
      //FIXME: Parse sample rate
      //SAMPLE_RATE = hz(args[++i].to!int());
    }
    else if (args[i] == "--verbose" || args[i] == "-v") {
      verbose = true;
    }
    else {
      halt("Unexpected argument: " ~ args[i]);
    }
  }

  if (outputMode == OutputMode.AU) {
    rawWrite2(".snd");
    rawWrite2([cast(uint)24.bigEndian, 0xffffffff, 6.bigEndian, (cast(uint)SAMPLE_RATE.value).bigEndian, 2.bigEndian]);
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
int Duck(void function() fn) {
  spork(fn);
  return 0;
}
