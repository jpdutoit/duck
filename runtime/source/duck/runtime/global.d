module duck.runtime.global;

import core.stdc.stdlib : exit;

enum OutputMode {
  None,
  AU,
  PortAudio
}

__gshared OutputMode outputMode;

__gshared float SAMPLE_RATE = 48000;
