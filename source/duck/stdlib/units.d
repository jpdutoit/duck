module duck.stdlib.units;

import duck.stdlib;

import std.string : format;
import std.math;
import core.time;
import std.traits: isNumeric;

import duck.runtime.model, duck.global;

alias mono = float;
alias stereo = float[2];

alias range = float[2];

auto scale(double min, double max, T)(T t, range r)
{
  return (t - min) / (max-min) * (r[1]-r[0]) + r[0];
}

/*struct Range(T) {
  T min;
  T max;
  this(T _min, T _max) {
    min = _min;
    max = _max;
  }
};

Range!float range(float a, float b) {
  return Range!float(a, b);
}*/
///10 - (now % 10) => now;

struct Time {
  double samples;
  alias value = samples;

  this(Duration d) {
    samples = d.samples;
  }
  void opAssign(Duration d) {
    samples = d.samples;
  }


  static Time withSamples(double samples) {
    Time t;
    t.samples = samples;
    return t;
  }

  Duration opBinary(string op:"%")(auto ref Duration other) {
    return Duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  Duration opBinary(string op:"-")(auto ref Time other) {
    return Duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  Time opBinary(string op)(auto ref Duration other) if (op != ">>") {
    return Time.withSamples(mixin("samples"~op~"other.samples"));
  }
  Time opBinary(string op)(auto ref Time other) if (op != ">>") {
    return Time.withSamples(mixin("samples"~op~"other.samples"));
  }
  int opCmp(Time other) {
    return samples < other.samples ? -1 : samples > other.samples ? 1 : 0;
  }
  string toString() {
    return format("%fs (%f samples)", samples / SAMPLE_RATE, samples);
  }
}

struct Duration {
  double samples;
  alias value = samples;

  static Duration withSamples(double samples) {
    Duration t;
    t.samples = samples;
    return t;
  }
  /*Duration opBinary(string op:"%")(auto ref Duration other) {
    return Duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  Duration opBinary(string op)(auto ref Duration other) if (op != ">>") {
    return Duration.withSamples(mixin("samples"~op~"other.samples"));
  }
  Time opBinary(string op)(auto ref Time other)  if (op != ">>") {
    return Time.withSamples(mixin("samples"~op~"other.samples"));
  }*/
  int opCmp(Duration other) {
    return samples < other.samples ? -1 : samples > other.samples ? 1 : 0;
  }
  string toString() {
    return format("%fs (%s samples)", samples / SAMPLE_RATE, samples);
  }
  mixin UnitOperators mix;
};

@property
Duration seconds(double s) {
  return Duration(s * SAMPLE_RATE.value);
}

@property
Duration samples(double s) {
  return Duration(s);
}

@property
Duration ms(float ms) {
  return Duration(ms / 1000 * SAMPLE_RATE.value);
}

/*
void advance(Duration s) {

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
    if (isNumeric!T)
  {
    pragma(inline, true);
    return typeof(this)(mixin("this.value"~op~"rhs"));
  }

  auto opBinaryRight(string op, T)(auto ref T lhs)
    if (isNumeric!T)
  {
    pragma(inline, true);
    return typeof(this)(mixin("lhs"~op~"this.value"));
  }

  auto opCast(T)()
    if (isNumeric!T)
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
    freq.value = 440 * pow(2, n.index - 49);;
    return freq;
  }

  /*this(float f) {
  	value = f;
  }
  this(Note n) {
  	value = 440 * pow(2, n.index - 49);
  }*/

  /*void opAssign(Note n) {

    value = 440 * pow(2, n.index - 49);
  }*/

  mixin UnitOperators mix;

  //alias value this;
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
