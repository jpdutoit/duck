module duck.runtime.model;

public import duck.runtime.registry;

mixin template UGEN(Impl) {
public:
  ~this() {
    UGenRegistry.deregister(&this);
  }

  template opDispatch(string name : "isEndPoint") {
    static enum opDispatch = false;
  }

  alias void delegate(ulong) __ConnDg;

  ulong __sampleIndex = ulong.max;
  __ConnDg[] __connections;

  void __tick(ulong nextSampleIndex) {
    //writefln("sampleIndex=%s, nextSampleIndex=%s, connections.length=%s", __sampleIndex, nextSampleIndex,  __connections.length);
    if (__sampleIndex == nextSampleIndex)
      return;

    __sampleIndex = nextSampleIndex;
    // Process connections
    for (int c = 0; c < __connections.length; ++c) {
      __connections[c](nextSampleIndex);
      //__connections[c].execute(nextSampleIndex);
    }
    //writefln("%s", s);
    static if (is(typeof(&this.tick))) {
      tick();
    }
  }

  void __add(__ConnDg dg) {
    UGenRegistry.register(&this);
    __connections ~= dg;
  }
}
