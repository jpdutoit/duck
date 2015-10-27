module duck.registry;
import std.stdio;

interface Connection {
  void execute(ulong sampleIndex);
};

struct UGenInfo {
  ulong sampleIndex = ulong.max;
  bool endpoint;
  void delegate() ugenTick;
  Connection[] connections;

  void tick(ulong nextSampleIndex) {
    //writefln("sampleIndex=%s, nextSampleIndex=%s, connections.length=%s", sampleIndex, nextSampleIndex,  connections.length);
    if (sampleIndex == nextSampleIndex)
      return;
    
    sampleIndex = nextSampleIndex;
    // Process connections
    for (int c = 0; c < connections.length; ++c) {
      connections[c].execute(nextSampleIndex);
    }
    //writefln("%s", s);
    if (ugenTick)
      ugenTick();
  }
};

struct UGenRegistry {
  static UGenInfo*[void*] all;
  static UGenInfo*[void*]endPoints;

  static ref UGenInfo register(T)(T* obj) {
    //writefln("Register UGEN: %s %s", T.stringof, obj); stdout.flush();
    UGenInfo *info;
    if (obj !in all) {
      info = new UGenInfo();
      //info.object = obj;
      //info.size = (*obj).sizeof;
      info.endpoint = T.isEndPoint;
      //pragma(msg, "Register ", T); 
      static if (is(typeof(&obj.tick)))
        info.ugenTick = &obj.tick;

      all[obj] = info;
      //writefln("Registered UGEN: %s %s", T.stringof, obj); stdout.flush();

      if (info.endpoint)
        endPoints[obj] = info;
    } 
    else info = all[obj];
    return *info;
  }



  static void deregister(T)(T* obj) {
    //writefln("Deregistered UGEN: %s %s", T.stringof, obj);
    if (obj in all) {
      UGenInfo *info = all[obj];
      all.remove(obj);
      if (info.endpoint)
        endPoints.remove(obj);
    }

  }
};
