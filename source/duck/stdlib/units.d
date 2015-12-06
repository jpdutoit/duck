module duck.stdlib.units;

import core.time;
import duck.stdlib;
import duck.runtime;
import duck.runtime.model;
import duck.global;

nothrow:

alias mono = float;
alias stereo = float[2];
alias range = float[2];

auto scale(double min, double max, T)(T t, range r)
{
  return (t - min) / (max-min) * (r[1]-r[0]) + r[0];
}


struct Time {
  double samples;
  alias value = samples;

  this(duration d) {
    samples = d.samples;
  }
  void opAssign(duration d) {
    samples = d.samples;
  }


  static Time withSamples(double samples) {
    Time t;
    t.samples = samples;
    return t;
  }

  duration opBinary(string op:"%")(auto ref duration other) {
    return duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  duration opBinary(string op:"-")(auto ref Time other) {
    return duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  Time opBinary(string op)(auto ref duration other) if (op != ">>") {
    return Time.withSamples(mixin("samples"~op~"other.samples"));
  }
  Time opBinary(string op)(auto ref Time other) if (op != ">>") {
    return Time.withSamples(mixin("samples"~op~"other.samples"));
  }
  int opCmp(Time other) {
    return samples < other.samples ? -1 : samples > other.samples ? 1 : 0;
  }
}

struct duration {
  double samples;
  alias value = samples;

  static duration withSamples(double samples) {
    duration t;
    t.samples = samples;
    return t;
  }
  /*duration opBinary(string op:"%")(auto ref duration other) {
    return duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  duration opBinary(string op)(auto ref duration other) if (op != ">>") {
    return duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  Time opBinary(string op)(auto ref Time other)  if (op != ">>") {
    return Time.withSamples(mixin("samples"~op~"other.samples"));
  }*/
  int opCmp(duration other) {
    return samples < other.samples ? -1 : samples > other.samples ? 1 : 0;
  }
  mixin UnitOperators mix;
};

@property
duration seconds(double s) {
  return duration(s * SAMPLE_RATE.value);
}

@property
duration samples(double s) {
  return duration(s);
}

@property
duration ms(float ms) {
  return duration(ms / 1000 * SAMPLE_RATE.value);
}

/*
void advance(duration s) {

}*/

struct Note {
  float index;
}


auto bpm(double bpm) {
  return frequency(bpm / 60.0);
  //return bpm / 60.0;
}

Note note(float n) {
  return Note(n);
}

enum isNumber(T) = false;
enum isNumber(T : float) = true;
enum isNumber(T : double) = true;
enum isNumber(T : int) = true;
enum isNumber(T : long) = true;

mixin template UnitOperators() {
  auto opBinary(string op)(auto ref typeof(this) rhs) if (op=="+" || op=="-"){
    pragma(inline, true);
    return typeof(this)(mixin("this.value"~op~"rhs.value"));
  }

  auto opBinary(string op:"/")(auto ref typeof(this) rhs) {
    pragma(inline, true);
    return mixin("cast(double)this.value"~op~"rhs.value");
  }

  auto opBinary(string op, T)(auto ref T rhs)
    if (isNumber!T)
  {
    pragma(inline, true);
    return typeof(this)(mixin("this.value"~op~"rhs"));
  }

  auto opBinaryRight(string op, T)(auto ref T lhs)
    if (isNumber!T)
  {
    pragma(inline, true);
    return typeof(this)(mixin("lhs"~op~"this.value"));
  }

  auto opCast(T)()
    if (isNumber!T)
  {
    pragma(inline, true);
    return cast(T)value;
  }

}

struct frequency {
  float value;

  static opCall(float f) {
    pragma(inline, true);
    frequency freq;
    freq.value = f;
    return freq;
  }

  static opCall(Note n) {
    pragma(inline, true);
    frequency freq;
    freq.value = 440 * powf(2, n.index - 49);;
    return freq;
  }

  mixin UnitOperators mix;
}

unittest {
  assert(note(49).index == 49);
  assert(frequency(note(49)) == 440.hz);
}

frequency hz(float f) {
  return frequency(f);
}



unittest {
  frequency f1 = frequency(10);
  frequency f2 = frequency(20);
  assert(frequency(20) == 2 * f1);
  assert(frequency(20) == f1 * 2);
  assert(cast(double)f1 == 10);
}
