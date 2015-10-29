module duck;

public import duck.global;

version(USE_PORT_AUDIO) {
  public import duck.pa;
}

public import duck.ugens;
public import duck.scheduler;
public import duck.units;
public import duck.runtime.model;
public import duck.entry;
public import duck.scales;
