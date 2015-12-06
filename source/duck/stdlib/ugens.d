module duck.stdlib.ugens;

import duck.runtime, duck.stdlib, duck.global, duck.osc;
//public import std.math;


enum PI = 3.14159265359;

struct Value(T) {
  T value;

  alias value input;
  alias value output;

  this(T t) {
    value = t;
  }
  mixin UGEN!(Value!T);
};

alias Mono = Value!mono;
alias Stereo = Value!stereo;
alias Float = Value!float;
alias Frequency = Value!frequency;


///////////////////////////////////////////////////////////////////////////////

struct WhiteNoise {
  mono output = 0;

  void tick() {
    //import std.random : uniform;
    //output = uniform(-1.0, 1.0);
  }
  mixin UGEN!WhiteNoise;
}

///////////////////////////////////////////////////////////////////////////////
 uint bigEndian(uint value) {
        return value << 24
          | (value & 0x0000FF00) << 8
          | (value & 0x00FF0000) >> 8
          | value >> 24;
    }

uint bigEndian(float fvalue) {
  uint value = *cast(uint*)&fvalue;
        return value << 24
          | (value & 0x0000FF00) << 8
          | (value & 0x00FF0000) >> 8
          | value >> 24;
    }

/*struct AuWriter {
  enum isEndPoint = true;

  mono input = 0;
  mono output = 0;

  @disable this();

  this(string filename) {
    file = File("./" ~ filename, "w");
    file.rawWrite(".snd");
    file.rawWrite([cast(uint)24.bigEndian, 0xffffffff, 6.bigEndian, SAMPLERATE.bigEndian, 1.bigEndian]);
  }

  void tick() {
    output = input;
    //writefln("input %s", input);
    buffer[index] = input.bigEndian;
    index = (index + 1) % buffer.length;
    if (index == 0) {
      //writefln("b %s", buffer);
      file.rawWrite(buffer);
    }
  }
private:
  File file;
  size_t index = 0;
  uint[64] buffer;

  mixin UGEN!AuWriter;
};*/

struct Pat {
  mono trigger = 0;
  alias input = trigger;
  mono output = 0;

  string pattern;
  this(string s) {
    //pattern = s.replace(" ", "");
    phase = pattern.length - 0.000001;
  }
  double phase = 1.0;
  ulong index = 0;

  void tick() {
    if (input) {
      while (pattern[index] == ' ')
        index = (index + 1) % pattern.length;
      output = pattern[index] != '.';
      index = (index + 1) % pattern.length;
      //if (output)
       // writefln("b, %s %s", now.time, index);
    }
    else output = 0;
    /*double delta = cast(double)_freq / SAMPLE_RATE;
    bool change = floor(phase + delta) > floor(phase);
    phase = (phase + delta);
    if (change) {
      //writefln("%s %s %s", floor(phase), floor(phase - delta), change);
      phase %= pattern.length;
      if (pattern[cast(int)(phase) % pattern.length] != '.')
        output = 1;
      else
        output = 0;
      index++;
    } else {
      output = 0;
    }
    */

  }

  mixin UGEN!Pat;
};

struct Log {
  mono input = 0;
  mono output = 0;

  string message;
  this(string s) {
    message = s;
  }
  void tick() {

    if (input != output) {
      print(message, ":", input);
      output = input;
    }
    //writefln("%s, %s", input, output);
  }

  mixin UGEN!Log;
};

struct SAH {
  mono input = 0;
  mono trigger = 0;
  mono output = 0;

  void tick() {
    if (trigger > 0.0) {
      output = input;
      //writefln("%s", output);
    }
  }
  mixin UGEN!SAH;
}
///////////////////////////////////////////////////////////////////////////////

struct Pan {
  mono input = 0;
  stereo output;
  float pan = 0;

  void tick() {
    float p = (pan + 1.0) / 2.0;
    output[0] = input * cos(p * PI / 2);
    output[1] = input * sin(p * PI / 2);
  }
  mixin UGEN!Pan;
}

///////////////////////////////////////////////////////////////////////////////

struct Gain {
  float gain = 1.0;
  mono input = 0;
  mono output = 0;

  void tick() {
    output = input * gain;
  }

  mixin UGEN!Gain;
}

///////////////////////////////////////////////////////////////////////////////
/*
struct SinOsc {
  this(frequency freq, range r) {
    freq = freq;
    range = r;
  }

  this(frequency f, mono min = -1, mono max = 1) {
    freq = f;
    min = min;
    max = max;
  }
  frequency freq = 440.hz;
  mono output = 0;
  double phase = 0;
  alias input = freq;
  //float min = -1;
  //float max = 1;

  union {
    struct {
      float min = -1;
      float max = 1;
    }
    range range;
  }

  void tick() {
    double delta = (freq / SAMPLE_RATE);
    output = scale!(-1, 1)(sin(phase * 2 * PI), range);
    phase = (phase + delta) % 1.0;
    //writefln("sinonsc %s", output);
    //_output = (sin(phase * 2 * PI) + 1) / 2 * (max - min) + min;
  }

  mixin UGEN!SinOsc;
}*/

///////////////////////////////////////////////////////////////////////////////

struct Pitch {
  mono input;
  frequency output;

  void tick() {
    output = frequency(440 * powf(2, (input - 49)/ 12));
  }
  mixin UGEN!Pitch;
};

struct SawTooth {
  frequency freq = 440.hz;
  mono output = 0;
  double phase = 0;
  alias input = freq;
  float min = -1;
  float max = 1;

  void tick() {
    double delta = freq / SAMPLE_RATE;
    phase = (phase + delta) % 1.0;
    output = phase * (max - min) + min;
    //_output = sin(phase * 2 * PI);
  }

  mixin UGEN!SawTooth;
}


struct Square {
  frequency freq = 440.hz;
  mono output = 0;
  double phase = 0;
  alias input = freq;
  float min = -1;
  float max = 1;

  void tick() {
    double delta = freq / SAMPLE_RATE;
    phase = (phase + delta) % 1.0;
    output = phase < 0.5f ? max : min;
    //_output = sin(phase * 2 * PI);
  }

  mixin UGEN!Square;
}
/*
struct Triangle {
  frequency freq = 440.hz;
  mono output = 0;
  double phase = 0;
  alias input = freq;
  float min = -1;
  float max = 1;

  void tick() {
    double delta = freq / SAMPLE_RATE;
    phase = (phase + delta) % 1.0;
    output = abs(phase * 2 - 1.0) * (max - min) + min;
    //_output = sin(phase * 2 * PI);
  }

  mixin UGEN!Triangle;
}
*/
struct ScaleQuant {
  short[] scale = [0, 2, 4, 5, 7, 9, 11];
  float key = 49;
  mono output = 0;
  mono input = 0;

  this(Key)(Key key, short[] scale) {
    //key.output >> this.key;
    //pipe(key.output, this.key);
    scale = scale;
  }
  this(int key, short[] scale) {
    key = key;
    scale = scale;
  }

  void tick() {
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

struct Quant {
  mono output = 0;
  mono input = 0;

  void tick() {
    output = roundf(input);
    //_output = round((input - min) / (max - min) * levels) / levels * (max - min) + min;
  }

  mixin UGEN!Quant;
}
///////////////////////////////////////////////////////////////////////////////

struct Clock {
  mixin UGEN!Clock;

  this(frequency freq) {
    freq = freq;
  }

  //this(T)(T freq) {
    //pipe(freq, this.freq);
  //}

  frequency freq = 1.hz;
  alias input = freq;
  mono output = 1;
  double phase = 1.0;

  void tick() {
    double delta = freq / SAMPLE_RATE;
    phase = (phase + delta);
    //if (phase > 0.99 || phase < 0.01)
    //writefln(" , %s %s", now.time, phase);
    if (phase >= 1.0) {
      phase = phase - 1;
      phase %= 1.0;
      output = 1;
      //writefln("c, %s %s", now.time, phase);
    } else {
      output = 0;
    }

  }
};

struct ADSR {
  mixin UGEN!ADSR;

  mono attack = 1000;
  mono decay = 1000;
  mono sustain = 0.7f;
  mono release = 1000;

  mono input = 0;
  mono output = 0;

  void tick() {
    //writefln("%s %s %s", elapsed, input, lastInput);
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


struct AR {
  mixin UGEN!AR;

  duration attack = 1000.samples;
  duration release = 1000.samples;

  mono input = 0;
  mono output = 0;

  void tick() {
    //writefln("%s %s %s", elapsed, input, lastInput);
    if (input > 0 && lastInput <= 0) {
      elapsed = 0.samples;
      att = attack;
      rel = release;
      lastInput = input;
    }
    if (input <= 0 && lastInput > 0) {
      if (elapsed >= att) {
        elapsed = 0.samples;
        lastInput = input;
      }
    }


    if (lastInput > 0) {
      // ADS
      if (elapsed < att) {
        output += (1 - output) * 1.samples / (att - elapsed);
      } else {
        output = 1.0;
        return;
      }
    } else {
      // R
      if (elapsed < rel) {
        output += (0 - output) * 1.samples / (rel - elapsed);
      }
      else {
        output = 0;
        return;
      }
    }
    elapsed = elapsed + 1;
  }

//private:
  duration att = 0.samples, rel = 0.samples;
  mono lastInput = 0;
  duration elapsed = 0.samples;
}

struct Delay {
  mixin UGEN!Delay;
  this(ulong samples) {
    this.buffer.length = samples;
    for (size_t i = 0; i < samples; ++i) {
      this.buffer[i] = 0;
    }
    index = 0;
  }

  mono input = 0;
  mono output = 0;

  void tick() {
    output = buffer[index];
    buffer[index] = input;
    index = (index + 1) % buffer.length;
  }
private:
  size_t index = 0;
  mono[] buffer;
};



struct Echo {
  mixin UGEN!Echo;

  this(ulong samples) {
    delay = Delay(samples);
  }

  mono input = 0;
  mono output = 0;
  float gain = 0.5;

  void tick() {
    delay.input = input + delay.output * gain;
    delay.tick();
    output = delay.output + input;
  }
private:
  Delay delay;
  //mono[] buffer;
};
///////////////////////////////////////////////////////////////////////////////

struct ADC {
  mono output;

  void tick() {
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
  this(float[] expected, int line = __LINE__) {
    this.expected = expected;
    this.received.length = expected.length;
    this.line = line;
  }

  this(float expected, int line = __LINE__) {
    this.expected = [expected];
    this.received.length = this.expected.length;
    this.line = line;
  }

  mono input;
  alias output = input;

  void tick() {
    if (failed) return;
    received[index % expected.length] = input;
    index++;
    if (index % expected.length == 0) {
      for (int i = 0; i < expected.length; ++i) {
        if (fabs(expected[i] - received[i]) > 1e-5) {
          print("(", line, ") \033[0;31mExpected ");
          print(this.expected, ", got ", this.received, " at index ", index - expected.length, "\033[0m\n");
            //writefln("(%d) \033[0;31mExpected %s, got %s at index %d\033[0m", line, this.expected, this.received, index - expected.length);
            failed = true;
            break;
        }
      }
    }

    /*if (input == cast(long)_input)
      //writef("%d ", cast(long)_input);
    else
      //writef("%f ", input);*/
  }
  mixin UGEN!Assert;

  static enum isEndPoint = true;
private:
  bool failed = false;
  float[] expected;
  float[] received;
  int line;
  int index = 0;
};


struct Printer {
  mono input;

  void tick() {
    if (input == cast(long)input)
      print(cast(long)input);
      //stderr.writef("%d ", cast(long)_input);
    else
      print(input);
      //stderr.writef("%f ", input);
  }
  mixin UGEN!Printer;

  static enum isEndPoint = true;
};

struct DAC {
  @disable this(this);

  union {
    struct {
      mono left = 0;
      mono right = 0;
    }
    stereo input;
  };



  void tick() {
    //.tick();
    //if (left > 0)
    //print(left);
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
      }

      //writefln("%s", input);
      //
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

struct OSCValue {
  mono output = 0;

  this(string target) {
    this.target = target;
  }

  void tick() {
    OSCMessage *msg = oscServer.get(target);
    if (msg) {
      msg.read(0, &output);
      //stderr.writefln("Set trigger to %s", output);
    }
  }
  mixin UGEN!OSCValue;
;
private:
  string target;
}
