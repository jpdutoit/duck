module duck.global;

import duck.units;

__gshared frequency SAMPLE_RATE = 44100.hz;

enum OutputMode {
  AU,
  PortAudio
}

__gshared OutputMode outputMode;

__gshared bool verbose = false;

void log(lazy string s) {
  if (verbose) {
    import std.stdio : stderr;
    stderr.writeln(s);
  }
}

void warn(lazy string s) {
  import std.stdio : stderr;
  stderr.writeln(s);
}

void halt(lazy string s) {
  import core.stdc.stdlib : exit;
  warn(s);
  exit(1);
}
