module duck.entry;
import duck.runtime, std.stdio : stderr;
import duck.stdlib;
import duck.stdlib.ugens : bigEndian;
import std.conv : to;

void initialize(string args[]) {

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
			i++;
			SAMPLE_RATE = hz(args[i].to!int());
		}
		else if (args[i] == "--verbose" || args[i] == "-v") {
			verbose = true;
		}
		else {
			halt("Unexpected argument: " ~ args[i]);
		}
	}

	if (outputMode == OutputMode.AU) {
		stdout.rawWrite(".snd");
		stdout.rawWrite([cast(uint)24.bigEndian, 0xffffffff, 6.bigEndian, (cast(uint)SAMPLE_RATE.value).bigEndian, 2.bigEndian]);
	}
	else if (outputMode ==  OutputMode.PortAudio) {
		version(USE_PORT_AUDIO) {
			audio.init();
		} else {
			halt("PortAudio support not compiled in.");
		}
	}
	log("Sample rate: " ~ SAMPLE_RATE.value.to!string);
}
int Duck(void function() fn) {
	//import std.stdio : writeln, stdout;

	//Graphiti.instance.init("test", false);
	spork(fn);
	//Graphiti.instance.close();
	return 0;
}
