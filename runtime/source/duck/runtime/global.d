module duck.runtime.global;

import core.stdc.stdlib : exit;

enum OutputMode {
  AU,
  PortAudio
}

__gshared OutputMode outputMode;
