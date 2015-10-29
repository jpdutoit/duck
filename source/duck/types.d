module duck.types;
private import std.traits : isImplicitlyConvertible;
import duck.units;

struct Tuple(E...)
{
  E values;
};

/*auto tuple(E...)(E e)
{
  return Tuple!E(e);
}*/

// Implicit conversion
struct ValueProc(Source, Target)
  if (isImplicitlyConvertible!(Source, Target))
{
  //pragma(msg, "VP", Source, " ", Target);
  static void set(ref Source src, ref Target tgt) {
    pragma(inline, true);
    //writefln("Copy %s to %s", Source.stringof, Target.stringof);
    tgt = src;
  }
}

// Implicit conversion - Array Case
struct ValueProc(Source : A[N], Target : B[N], A, B, int N)
  if (is(ValueProc!(A, B)))
  //if (isImplicitlyConvertible!(A, B))
{
  static void set(ref Source src, ref Target tgt) {
    pragma(inline, true);
    //writefln("Copy %s to %s", Source.stringof, Target.stringof);
    foreach(i; 0..N)
      ValueProc!(A, B).set(src[i], tgt[i]);
      //tgt[i] = src[i];
  }
}
/*
// Implicit conversion - Tuple to Array Case
struct ValueProc(Source : Tuple!A, Target : B[2], B, A...)
  if (isImplicitlyConvertible!(A[0], B) && isImplicitlyConvertible!(A[1], B))
{
  static void set(ref Source src, ref Target tgt) {
    pragma(msg, A);
    //writefln("Copy %s to %s", Source.stringof, Target.stringof);
    tgt[0] = src.values[0];
    tgt[1] = src.values[1];
    //foreach(i; 0..2)
      //tgt[i] = src.values[i];
  }
}*/

/*pragma(msg, "B");
struct ValueProc(Source, Target)
if (!isImplicitlyConvertible!(Source, Target) && !)
{
  pragma(msg, "A");
  static if (is(typeof(Source.value))) {// && is(isImplicitlyConvertible!(typeof(Source.value), Target))) {
    static if (isImplicitlyConvertible!(typeof(Source.value), Target)) {
      static void set(ref Source src, ref Target tgt) {
        tgt = src.value;
      }
      pragma(msg, "YEP1 ", Source, " ", Target, " ", is(typeof(Source.value)) , isImplicitlyConvertible!(typeof(Source.value), Target));
    }
  }
  /*else static if (is(typeof(Target.value))) {
    static if (isImplicitlyConvertible!(Source, typeof(Target.value))) {
      pragma(msg, "YEP2 ", Source, " ", Target, " ", is(typeof(Target.value)) , isImplicitlyConvertible!(Source, typeof(Target.value)));
      static void set(ref Source src, ref Target tgt) {
        tgt.value = src;
      }
    }
  }*/
//}
/*
struct ValueProc(Source, Target)
if (!isImplicitlyConvertible!(Source, Target) && is(typeof(
    (Source src, ref Target tgt)
    {
      tgt = src.value;
    })))
{
    static void set(ref Source src, ref Target tgt) {
      pragma(inline, true);
      tgt = src.value;
    }

}

struct ValueProc(Source, Target)
if (!isImplicitlyConvertible!(Source, Target) && is(typeof(
    (Source src, ref Target tgt)
    {
      tgt = Target(src);
    })))
{
    //pragma(msg, "YEP3 ", Source, " ", Target, " ", is(typeof(Target.value)) , isImplicitlyConvertible!(Source, typeof(Target.value)));
    static void set(ref Source src, ref Target tgt) {
      pragma(inline, true);
      tgt = Target(src);
    }

}*/
/*
struct ValueProc(Source, Target)
  if (is(typeof(Source.value)) && isImplicitlyConvertible!(typeof(Source.value), Target))
{
  static void set(Source src, auto ref Target tgt) {
    //writefln("Copy %s to %s: %s %s", Source.stringof, Target.stringof, src ,tgt);
    tgt = src.value;
  }
}

struct ValueProc(Source, Target)
  if (is(typeof(Target.value)) && isImplicitlyConvertible!(Source, typeof(Target.value)))
{
  static void set(Source src, auto ref Target tgt) {
    //writefln("Copy %s to %s: %s %s", Source.stringof, Target.stringof, src ,tgt);
    tgt.value = src;
  }
}*/


/*struct ValueProc(Source : Frequency, Target)
  if (isImplicitlyConvertible!(float, Target))
{
  static void set(ref Source src, ref Target tgt) {
    //writefln("Copy %s to %s: %s %s", Source.stringof, Target.stringof, src ,tgt);
    tgt = src.value;
  }
}*/


/*
// Mono to Multi channel
struct ValueProc(Source, Target : A[N], A, int N)
  if (is(ValueProc!(Source, A)) && N != 2)
  //if (isImplicitlyConvertible!(Source, A) && N!=20)
{
  static void set(ref Source src, ref Target tgt) {
    //writefln("Copy %s to %s: %s %s", Source.stringof, Target.stringof, src ,tgt);
    //pragma(inline, true);
    foreach(i; 0..N)
      ValueProc!(Source, A).set(src, tgt[i]);
      //tgt[i] = src;
  }
}
*/
struct ValueProc(Source, Target : A[N], A, int N)
  if (N == 2 && is(ValueProc!(Source, A)))
{
  static void set(ref Source src, ref Target tgt) {
    //writefln("Copy %s to %s: %s %s", Source.stringof, Target.stringof, src ,tgt);
    pragma(inline, true);
    ValueProc!(Source, A).set(src, tgt[0]);
    ValueProc!(Source, A).set(src, tgt[1]);
    //tgt[0] = src;
    //tgt[1] = src;
  }
}

struct ValueProc(Source, Target : A[N], A, int N)
  if (N == 3 && is(ValueProc!(Source, A)))
{
  static void set(ref Source src, ref Target tgt) {
    //writefln("Copy %s to %s: %s %s", Source.stringof, Target.stringof, src ,tgt);
    pragma(inline, true);
    ValueProc!(Source, A).set(src, tgt[0]);
    ValueProc!(Source, A).set(src, tgt[1]);
    ValueProc!(Source, A).set(src, tgt[2]);
  }
}

unittest {
  static assert(is(ValueProc!(float, float)));
  static assert(is(ValueProc!(double, float)));
  static assert(is(ValueProc!(double, double)));
  static assert(is(ValueProc!(double, double[2])));
  static assert(is(ValueProc!(float, double[2])));
  static assert(is(ValueProc!(double, float[2])));
}

//
