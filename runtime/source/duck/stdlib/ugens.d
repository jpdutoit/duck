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

struct Pan {

  auto initialize() nothrow { return &this; }

  mono input = 0;
  stereo output;
  float pan = 0;

  void tick() nothrow {
    float p = (pan + 1.0) / 2.0;
    output[0] = input * cos(p * PI / 2);
    output[1] = input * sin(p * PI / 2);
  }
  mixin UGEN!Pan;
}

///////////////////////////////////////////////////////////////////////////////

struct ScaleQuant {

  auto initialize() nothrow { return &this; }

  short[] scale = [0, 2, 4, 5, 7, 9, 11];
  float key = 49;
  mono output = 0;
  mono input = 0;

  auto initialize(Key)(Key key, short[] scale) nothrow {
    //key.output >> this.key;
    //pipe(key.output, this.key);
    scale = scale;
    return &this;
  }
  auto initialize(int key, short[] scale) nothrow {
    key = key;
    scale = scale;
    return &this;
  }

  void tick() nothrow {
    int len = cast(int)scale.length;
    int index = cast(int)floorf((input - key) * len / 12);
    int mod = cast(int)((index + len*10000) % len);
    int note = scale[mod];
    int index2 = cast(int)((index - mod) / len * 12 + note) + cast(int)key;
    output = index2;
    //writefln("%s %s %s %s %s", input, index, index-mod, note, index2);
    //_output = round((input - min) / (max - min) * levels) / levels * (max - min) + min;
  }

  mixin UGEN!ScaleQuant;
}

///////////////////////////////////////////////////////////////////////////////

struct ADSR {
  mixin UGEN!ADSR;

  auto initialize() nothrow { return &this; }

  mono attack = 1000;
  mono decay = 1000;
  mono sustain = 0.7f;
  mono release = 1000;

  mono input = 0;
  mono output = 0;

  void tick() nothrow {
    //writefln("%s %s %s", elapsed, input, ©put);
    if (input > 0 && lastInput <= 0) {
      elapsed = 0;
      att = attack;
      dec = decay;
      sus = sustain;
      rel = release;
      lastInput = input;
    }
    if (input <= 0 && lastInput > 0) {
      if (elapsed >= att + dec) {
        elapsed = 0;
        output = sus;
        lastInput = input;
      }
    }


    if (lastInput > 0) {
      // ADS
      if (elapsed < att) {
        output += (1 - output) / (att - elapsed);
      } else if (elapsed < att + dec) {
        output += (sus - output)  / (att + dec - elapsed);
      } else {
        output = sus;
        return;
      }
    } else {
      // R
      if (elapsed < rel) {
        output += (0 - output) / (rel - elapsed);
      }
      else {
        output = 0;
        return;
      }
    }
    elapsed++;
  }

//private:
  mono att = 0, dec = 0, sus = 0, rel = 0;
  mono lastInput = 0;
  mono elapsed = 0;
}

///////////////////////////////////////////////////////////////////////////////

struct AR {
  mixin UGEN!AR;

  auto initialize() nothrow { return &this; }

  float attack = 1000;
  float release = 1000;

  mono input = 0;
  mono output = 0;

  void tick() nothrow {
    //writefln("%s %s %s", elapsed, input, lastInput);
    if (input > 0 && lastInput <= 0) {
      elapsed = 0;
      att = attack;
      rel = release;
      lastInput = input;
    }
    if (input <= 0 && lastInput > 0) {
      if (elapsed >= att) {
        elapsed = 0;
        lastInput = input;
      }
    }


    if (lastInput > 0) {
      // ADS
      if (elapsed < att) {
        float tmp = ((1 - output) * 1);
        output += tmp / (att - elapsed);
      } else {
        output = 1.0;
        return;
      }
    } else {
      // R
      if (elapsed < rel) {
        output += (0 - output) * 1 / (rel - elapsed);
      }
      else {
        output = 0;
        return;
      }
    }
    elapsed = elapsed + 1;
  }

//private:
  float att = 0, rel = 0;
  mono lastInput = 0;
  float elapsed = 0;
}

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

struct DAC {
  @disable this(this);

  auto initialize() { return &this; }

  union {
    struct {
      mono left = 0;
      mono right = 0;
    }
    stereo input;
  };

  void tick() nothrow {
    buffer[index++] = input;
    if (index == 64) {
      final switch(outputMode) {
        case OutputMode.AU: {
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

      index = 0;
    }
  }
  mixin UGEN!DAC;

  static enum isEndPoint = true;
private:
  uint[64*2] writeBuffer;
  stereo[64] buffer;
  int index;

};
