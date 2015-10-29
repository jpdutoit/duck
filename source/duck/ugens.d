module duck.ugens;

import std.math, std.random, std.stdio, std.array;

import duck, duck.runtime.model, duck.units, duck.global, duck.scheduler;


struct Value(T) {
  T _value;

  alias _value _input;
  alias _value _output;

  this(T t) {
    _value = t;
  }
  mixin UGEN!(Value!T);
};

alias Mono = Value!mono;
alias Stereo = Value!stereo;
alias Float = Value!float;
alias Frequency = Value!frequency;


///////////////////////////////////////////////////////////////////////////////

struct WhiteNoise {
  mono _output = 0;

  void tick() {
    _output = uniform(-1.0, 1.0);
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

  mono _input = 0;
  mono _output = 0;

  @disable this();

  this(string filename) {
    file = File("./" ~ filename, "w");
    file.rawWrite(".snd");
    file.rawWrite([cast(uint)24.bigEndian, 0xffffffff, 6.bigEndian, SAMPLE_RATE.bigEndian, 1.bigEndian]);
  }

  void tick() {
    _output = _input;
    //writefln("input %s", _input);
    buffer[index] = _input.bigEndian;
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
  mono _trigger = 0;
  alias _input = _trigger;
  mono _output = 0;

  string pattern;
  this(string s) {
    pattern = s.replace(" ", "");
    _phase = pattern.length - 0.000001;
  }
  double _phase = 1.0;
  ulong _index = 0;

  void tick() {
    if (_input) {
      _output = pattern[_index] != '.';
      _index = (_index + 1) % pattern.length;
      //if (_output)
       // writefln("b, %s %s", now.time, _index);
    }
    else _output = 0;
    /*double delta = cast(double)_freq / SAMPLE_RATE;
    bool change = floor(_phase + delta) > floor(_phase);
    _phase = (_phase + delta);
    if (change) {
      writefln("%s %s %s", floor(_phase), floor(_phase - delta), change);
      _phase %= pattern.length;
      if (pattern[cast(int)(_phase) % pattern.length] != '.')
        _output = 1;
      else
        _output = 0;
      index++;
    } else {
      _output = 0;
    }
    */

  }

  mixin UGEN!Pat;
};

struct Log {
  mono _input = 0;
  mono _output = 0;

  string message;
  this(string s) {
    message = s;
  }
  void tick() {

    if (_input != _output) {
      writeln(message, ":", _input);
      _output = _input;
    }
    //writefln("%s, %s", _input, _output);
  }

  mixin UGEN!Log;
};

struct SAH {
  mono _input = 0;
  mono _trigger = 0;
  mono _output = 0;

  void tick() {
    if (_trigger > 0.0) {
      _output = _input;
      //writefln("%s", _output);
    }
  }
  mixin UGEN!SAH;
}
///////////////////////////////////////////////////////////////////////////////

struct Pan {
  mono _input = 0;
  stereo _output;
  float _pan = 0;

  void tick() {
    float p = (_pan + 1.0) / 2.0;
    _output[0] = _input * cos(p * PI / 2);
    _output[1] = _input * sin(p * PI / 2);
  }
  mixin UGEN!Pan;
}

///////////////////////////////////////////////////////////////////////////////

struct Gain {
  float _gain = 1.0;
  mono _input = 0;
  mono _output = 0;

  void tick() {
    _output = _input * _gain;
  }

  mixin UGEN!Gain;
}

///////////////////////////////////////////////////////////////////////////////

struct SinOsc {
  this(frequency freq, range r) {
    _freq = freq;
    _range = r;
  }

  this(frequency f, mono min = -1, mono max = 1) {
    _freq = f;
    _min = min;
    _max = max;
  }
  frequency _freq = 440.hz;
  mono _output = 0;
  double _phase = 0;
  alias _input = _freq;
  //float _min = -1;
  //float _max = 1;

  union {
    struct {
      float _min = -1;
      float _max = 1;
    }
    range _range;
  }

  void tick() {
    double delta = (_freq / SAMPLE_RATE);
    _output = scale!(-1, 1)(sin(_phase * 2 * PI), _range);
    _phase = (_phase + delta) % 1.0;
    //writefln("sinonsc %s", _output);
    //_output = (sin(_phase * 2 * PI) + 1) / 2 * (_max - _min) + _min;
  }

  mixin UGEN!SinOsc;
}

///////////////////////////////////////////////////////////////////////////////

struct Pitch {
  mono _input;
  frequency _output;

  void tick() {
    _output = frequency(440 * pow(2, (_input - 49)/ 12));
  }
  mixin UGEN!Pitch;
};

struct SawTooth {
  frequency _freq = 440.hz;
  mono _output = 0;
  double _phase = 0;
  alias _input = _freq;
  float _min = -1;
  float _max = 1;

  void tick() {
    double delta = _freq / SAMPLE_RATE;
    _phase = (_phase + delta) % 1.0;
    _output = _phase * (_max - _min) + _min;
    //_output = sin(_phase * 2 * PI);
  }

  mixin UGEN!SawTooth;
}


struct Square {
  frequency _freq = 440.hz;
  mono _output = 0;
  double _phase = 0;
  alias _input = _freq;
  float _min = -1;
  float _max = 1;

  void tick() {
    double delta = _freq / SAMPLE_RATE;
    _phase = (_phase + delta) % 1.0;
    _output = _phase < 0.5f ? _max : _min;
    //_output = sin(_phase * 2 * PI);
  }

  mixin UGEN!Square;
}

struct Triangle {
  frequency _freq = 440.hz;
  mono _output = 0;
  double _phase = 0;
  alias _input = _freq;
  float _min = -1;
  float _max = 1;

  void tick() {
    double delta = _freq / SAMPLE_RATE;
    _phase = (_phase + delta) % 1.0;
    _output = abs(_phase * 2 - 1.0) * (_max - _min) + _min;
    //_output = sin(_phase * 2 * PI);
  }

  mixin UGEN!Triangle;
}

struct ScaleQuant {
  short[] _scale = [0, 2, 4, 5, 7, 9, 11];
  float _key = 49;
  mono _output = 0;
  mono _input = 0;

  this(Key)(Key key, short[] scale) {
    //key.output >> this.key;
    //pipe(key.output, this.key);
    _scale = scale;
  }
  this(int key, short[] scale) {
    _key = key;
    _scale = scale;
  }

  void tick() {
    int len = cast(int)_scale.length;
    int index = cast(int)floor((_input - _key) * len / 12);
    int mod = cast(int)((index + len*10000) % len);
    int note = _scale[mod];
    int index2 = cast(int)((index - mod) / len * 12 + note) + cast(int)_key;
    _output = index2;
    //writefln("%s %s %s %s %s", _input, index, index-mod, note, index2);
    //_output = round((_input - _min) / (_max - _min) * _levels) / _levels * (_max - _min) + _min;
  }

  mixin UGEN!ScaleQuant;
}

struct Quant {
  mono _output = 0;
  mono _input = 0;

  void tick() {
    _output = round(_input);
    //_output = round((_input - _min) / (_max - _min) * _levels) / _levels * (_max - _min) + _min;
  }

  mixin UGEN!Quant;
}
///////////////////////////////////////////////////////////////////////////////

struct Clock {
  mixin UGEN!Clock;

  this(frequency freq) {
    _freq = freq;
  }

  //this(T)(T freq) {
    //pipe(freq, this.freq);
  //}

  frequency _freq = 1.hz;
  alias _input = _freq;
  mono _output = 1;
  double _phase = 1.0;

  void tick() {
    double delta = _freq / SAMPLE_RATE;
    _phase = (_phase + delta);
    //if (_phase > 0.99 || _phase < 0.01)
    //writefln(" , %s %s", now.time, _phase);
    if (_phase >= 1.0) {
      _phase = _phase - 1;
      _phase %= 1.0;
      _output = 1;
      //writefln("c, %s %s", now.time, _phase);
    } else {
      _output = 0;
    }

  }
};

struct ADSR {
  mixin UGEN!ADSR;

  mono _attack = 1000;
  mono _decay = 1000;
  mono _sustain = 0.7f;
  mono _release = 1000;

  mono _input = 0;
  mono _output = 0;

  void tick() {
    //writefln("%s %s %s", elapsed, _input, lastInput);
    if (_input > 0 && lastInput <= 0) {
      elapsed = 0;
      att = _attack;
      dec = _decay;
      sus = _sustain;
      rel = _release;
      lastInput = _input;
    }
    if (_input <= 0 && lastInput > 0) {
      if (elapsed >= att + dec) {
        elapsed = 0;
        _output = sus;
        lastInput = _input;
      }
    }


    if (lastInput > 0) {
      // ADS
      if (elapsed < att) {
        _output += (1 - _output) / (att - elapsed);
      } else if (elapsed < att + dec) {
        _output += (sus - _output)  / (att + dec - elapsed);
      } else {
        _output = sus;
        return;
      }
    } else {
      // R
      if (elapsed < rel) {
        _output += (0 - _output) / (rel - elapsed);
      }
      else {
        _output = 0;
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

  Duration _attack = 1000.samples;
  Duration _release = 1000.samples;

  mono _input = 0;
  mono _output = 0;

  void tick() {
    //writefln("%s %s %s", elapsed, _input, lastInput);
    if (_input > 0 && lastInput <= 0) {
      elapsed = 0.samples;
      att = _attack;
      rel = _release;
      lastInput = _input;
    }
    if (_input <= 0 && lastInput > 0) {
      if (elapsed >= att) {
        elapsed = 0.samples;
        lastInput = _input;
      }
    }


    if (lastInput > 0) {
      // ADS
      if (elapsed < att) {
        _output += (1 - _output) * 1.samples / (att - elapsed);
      } else {
        _output = 1.0;
        return;
      }
    } else {
      // R
      if (elapsed < rel) {
        _output += (0 - _output) * 1.samples / (rel - elapsed);
      }
      else {
        _output = 0;
        return;
      }
    }
    elapsed = elapsed + 1;
  }

//private:
  Duration att = 0.samples, rel = 0.samples;
  mono lastInput = 0;
  Duration elapsed = 0.samples;
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

	mono _input = 0;
	mono _output = 0;

	void tick() {
		_output = buffer[index];
		buffer[index] = _input;
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

	mono _input = 0;
	mono _output = 0;
	float _gain = 0.5;

	void tick() {
		delay._input = _input + delay._output * _gain;
		delay.tick();
		_output = delay._output + _input;
	}
private:
	Delay delay;
	//mono[] buffer;
};
///////////////////////////////////////////////////////////////////////////////

struct ADC {
  mono _output;

  void tick() {
    if (++index == 64) {
      version(USE_PORT_AUDIO)
        audio.read(cast(void*)&buffer[0]);
      index = 0;
    }
    _output = buffer[index];
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

  mono _input;
  alias _output = _input;

  void tick() {
    if (failed) return;
    received[index % expected.length] = _input;
    index++;
    if (index % expected.length == 0) {
      for (int i = 0; i < expected.length; ++i) {
        if (fabs(expected[i] - received[i]) > 1e-5) {
            writefln("(%d) \033[0;31mExpected %s, got %s at index %d\033[0m", line, this.expected, this.received, index - expected.length);
            failed = true;
            break;
        }
      }
    }

    /*if (_input == cast(long)_input)
      writef("%d ", cast(long)_input);
    else
      writef("%f ", _input);*/
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
  mono _input;

  void tick() {
    if (_input == cast(long)_input)
      writef("%d ", cast(long)_input);
    else
      writef("%f ", _input);
  }
  mixin UGEN!Printer;

  static enum isEndPoint = true;
};

struct DAC {
  @disable this(this);

  union {
    struct {
      mono _left = 0;
      mono _right = 0;
    }
    stereo _input;
  };



  void tick() {
    //.tick();
    buffer[index++] = _input;
    if (index == 64) {
      final switch(outputMode) {
        case OutputMode.AU: {
          for (int i = 0; i < 64; ++i) {
            writeBuffer[i*2] = buffer[i][0].bigEndian;
            writeBuffer[i*2+1] = buffer[i][1].bigEndian;
          }
          stdout.rawWrite(writeBuffer);
          break;
        }
        case OutputMode.PortAudio: {
          version(USE_PORT_AUDIO)
            audio.write(cast(void*)buffer);
          break;
        }
      }

      //writefln("%s", _input);
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
