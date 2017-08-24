module duck.runtime.model;


alias TickDg = void delegate();

struct UGenRegistry {
  static void*[void*] all;
  static TickDg[void*]endPoints;

  static void register(void* obj, TickDg dg) {
    if (obj !in all) {
      import duck.runtime;
      //print("Register UGEN:");
      endPoints[obj] = dg;
      all[obj] = obj;
    }
  }

  static void deregister(void* obj) {
    if (obj in all) {
      all.remove(obj);
      endPoints.remove(obj);
    }

  }
};

__gshared ulong __idx = 0;


mixin template UGEN(Impl) {
public:
  ~this() {
    UGenRegistry.deregister(&this);
  }

  static Impl* alloc() {
    return new Impl();
  }

  template opDispatch(string name : "isEndPoint") {
    static enum opDispatch = false;
  }

  alias scope void delegate() @system __ConnDg;

  ulong __sampleIndex = ulong.max;
  __ConnDg[] __connections;

  void _tick() {
    // Only tick if we haven't previously
    if (__sampleIndex == __idx)
      return;

    __sampleIndex = __idx;

    // Process connections
    for (int c = 0; c < __connections.length; ++c) {
      __connections[c]();
    }
    static if (is(typeof(&this.tick))) {
      tick();
    }
  }

  void __add(scope void delegate() @system dg) {
    //UGenRegistry.register(&this);
    if (this.isEndPoint)
      UGenRegistry.register(cast(void*)&this, &this._tick);
    __connections ~= dg;
  }
}
alias scope void delegate() @system __ConnDg;
