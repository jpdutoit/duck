module duck.stdlib.units;

import core.time;
import duck.stdlib;
import duck.runtime;
import duck.runtime.model;
import duck.runtime.global;

nothrow:

alias mono = float;
alias stereo = float[2];
alias range = float[2];

alias Time = double;
alias duration = double;

alias note = float;
alias interval = float;
alias frequency = float;

T raw(T)(T t) { return t; }

/*
frequency frequency(Note n) {
  pragma(inline, true);
  frequency freq;
  freq.value = 440 * powf(2, n.index - 49);
  return freq;
}*/
