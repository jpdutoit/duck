module duck.stdlib.ugens;

import duck.runtime, duck.stdlib, duck.runtime.global;

enum PI = 3.14159265359;

struct Value(T) {
  T value;

  alias value input;
  alias value output;

  auto initialize(T t) nothrow {
    value = t;
    return &this;
  }
  mixin UGEN!(Value!T);
};

alias Mono = Value!mono;
alias Stereo = Value!stereo;
alias Float = Value!float;
alias Frequency = Value!float;

///////////////////////////////////////////////////////////////////////////////
 uint bigEndian(uint value) nothrow {
        return value << 24
          | (value & 0x0000FF00) << 8
          | (value & 0x00FF0000) >> 8
          | value >> 24;
    }

uint bigEndian(float fvalue) nothrow {
  uint value = *cast(uint*)&fvalue;
        return value << 24
          | (value & 0x0000FF00) << 8
          | (value & 0x00FF0000) >> 8
          | value >> 24;
    }


struct Pat {
  mono trigger = 0;
  alias input = trigger;
  mono output = 0;

  string pattern;
  auto initialize(string s) nothrow {
    pattern = s;
    phase = pattern.length - 0.000001;
    return &this;
  }
  double phase = 1.0;
  ulong index = 0;

  void tick() nothrow {
    if (input) {
      while (pattern[index] == ' ')
        index = (index + 1) % pattern.length;
      output = pattern[index] != '.';
      index = (index + 1) % pattern.length;
    }
    else output = 0;
  }

  mixin UGEN!Pat;
};

///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////

struct ADC {
  mono output;

  auto initialize() nothrow { return &this; }

  void tick() nothrow {
    if (++index == 64) {
      version(USE_PORT_AUDIO)
        audio.read(cast(void*)&buffer[0]);
      index = 0;
    }
    output = buffer[index];
  }

mixin UGEN!ADC;

private:
  mono[64] buffer;
  int index = 63;
}

///////////////////////////////////////////////////////////////////////////////

struct Assert {
  auto initialize() nothrow { return &this; }

  auto initialize(float[] expected, string file = __FILE__, int line = __LINE__) nothrow {
    this.expected = expected;
    this.received.length = expected.length;
    this.file = file;
    this.line = line;
    return &this;
  }

  auto initialize(float expected, string file = __FILE__, int line = __LINE__) nothrow {
    this.expected = [expected];
    this.received.length = this.expected.length;
    this.file = file;
    this.line = line;
    return &this;
  }

  mono input;
  alias output = input;

  void tick() nothrow {
    if (failed) return;
    received[index % expected.length] = input;
    index++;
    if (index % expected.length == 0) {
      for (int i = 0; i < expected.length; ++i) {
        if (fabs(expected[i] - received[i]) > 1e-5) {
          print(file);
          print("(", line, "): \033[0;31mExpected ");
          print(this.expected, ", got ", this.received, " at index ", index - expected.length, "\033[0m\n");
            //writefln("(%d) \033[0;31mExpected %s, got %s at index %d\033[0m", line, this.expected, this.received, index - expected.length);
            failed = true;
            break;
        }
      }
    }

  }
  mixin UGEN!Assert;

  static enum isEndPoint = true;
private:
  bool failed = false;
  float[] expected;
  float[] received;
  int line;
  int index = 0;
  string file;
};

///////////////////////////////////////////////////////////////////////////////

nothrow void outputAudioBuffer(stereo[64] buffer) {
  final switch(outputMode) {
    case OutputMode.AU: {
      uint[64*2] writeBuffer;
      for (int i = 0; i < 64; ++i) {
        writeBuffer[i*2] = buffer[i][0].bigEndian;
        writeBuffer[i*2+1] = buffer[i][1].bigEndian;
      }
      rawWrite2(writeBuffer);
      break;
    }
    case OutputMode.PortAudio: {
      version(USE_PORT_AUDIO)
        audio.write(cast(void*)buffer);
      break;
    }
    case OutputMode.None:
      break;
  }
}
