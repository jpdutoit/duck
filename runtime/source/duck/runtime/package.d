module duck.runtime;
public import duck.runtime.scheduler;
public import duck.runtime.model;
public import duck.runtime.entry;

public import duck.runtime.print;
version (USE_INSTRUMENTATION) {
  public import duck.runtime.instrument;
}

public import core.math;

//extern(C) double sin ( double x );
//extern(C) double cos ( double x );
extern(C) float floorf ( float );
//extern(C)
//float fabs ( float f ) {  return f >= 0 ? f : -f;};
extern(C) float roundf ( float );
extern(C) float powf (float, float );
alias abs = fabs;


public import duck.runtime.global;

version(USE_PORT_AUDIO) {
  public import duck.plugin.portaudio;
}
