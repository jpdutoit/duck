module duck.plugin.osc.ugen;

import duck.plugin.osc.server;
import duck.runtime.model;


struct OSCValue {
  float output = 0;

  this(string target) nothrow {
    this.target = target;
  }

  void tick() nothrow {
    OSCMessage *msg = oscServer.get(target);
    if (msg) {
      msg.read(0, &output);
      //stderr.writefln("Set trigger to %s", output);
    }
  }
  mixin UGEN!OSCValue;

private:
  string target;
}
