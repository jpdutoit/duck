module duck.runtime.model;


alias TickDg = void delegate() nothrow;
alias _ConnDg = void delegate() nothrow @system;

struct UGenRegistry {
  __gshared static void*[void*] all;
  __gshared static TickDg[void*]endPoints;

  static void register(void* obj, TickDg dg) nothrow {
    if (obj !in all) {
      //import duck.runtime;
      //print("Register UGEN:");
      endPoints[obj] = dg;
      all[obj] = obj;
    }
  }

  static void deregister(void* obj) nothrow {
    if (obj in all) {
      all.remove(obj);
      endPoints.remove(obj);
    }

  }
};

__gshared ulong _idx = 0;


mixin template UGEN(Impl) {
public:
  ~this() {
    UGenRegistry.deregister(&this);
  }

  static Impl* alloc() nothrow {
    return new Impl();
  }

  template opDispatch(string name : "isEndPoint") {
    static enum opDispatch = false;
  }

  ulong __sampleIndex = ulong.max;
  _ConnDg[] __connections;

  void _tick() nothrow @system {
    // Only tick if we haven't previously
    if (__sampleIndex == _idx)
      return;

    __sampleIndex = _idx;

    // Process connections
    for (int c = 0; c < __connections.length; ++c) {
      __connections[c]();
    }
    static if (is(typeof(&this.tick))) {
      tick();
    }
  }


  void _add(void delegate() nothrow @system dg) nothrow {
    //UGenRegistry.register(&this);
    if (this.isEndPoint)
      UGenRegistry.register(cast(void*)&this, &this._tick);
    __connections ~= dg;
  }
}

nothrow void _registerEndpoint(M)(M* mod){
  UGenRegistry.register(cast(void*)&mod, &mod._tick);
}
