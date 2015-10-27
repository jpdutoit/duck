module duck.model;

import duck.units, duck.types;
import std.traits : isBasicType;
import std.stdio; 
public import duck.registry;

enum bool hasOutput(T) = is(typeof(
    (inout int = 0)
    {
      typeof(T._output) r;
      auto a = r;
    })); 

enum bool hasInput(T) = is(typeof(
    (inout int = 0)
    {
      typeof(T._input) r;
      auto a = r;
      r = a;
    })); 

mixin template Operators() {
  auto opBinary(string op, R)(auto ref R r) if (op != ">>") {
    pragma(inline, true);
    return binary!op(this, r);
  }
  auto opBinaryRight(string op, R)(auto ref R r) if (op != ">>") {
    pragma(inline, true);
    return binary!op(r, this);
  }
};

class Pipe(E, T) : Connection {
  E expr;
  T *target;
  this(E _expr, T* _target) { 
    expr = _expr;
    target = _target;
  };

  void execute(ulong sampleIndex) {

    auto a = expr.eval(sampleIndex);
    //pragma (msg, expr.property, typeof(a), " => ", T);
    //writefln("%s %s >= %s", expr.property, a, target);
    pragma(msg, "ValueProc \n  ", typeof(a), " \n   ", T);
    ValueProc!(typeof(a), T).set(a, *target);
  }
};

unittest {
  Float a = 2, b = 3;
  auto d = a.value + b.value;
  int aa = 3;
  
  //auto a = v + 5;
}

struct Slot(Target)
{
  UGenInfo *ownerInfo;
  Target *property;

  @property auto eval(ulong sampleIndex) { 
    ownerInfo.tick(sampleIndex);
    return *property; 
  }

  mixin Operators;
  
  auto ref opBinaryRight(string op:">>", P)(P other) {
    pragma(inline, true);
    return pipe(other, this);
  }

  /*auto ref opBinaryRight(string op:">>", P : Tuple!F, F...)(P other) {
    static assert(is(Target: E[], E), "Can only assign a tuple to array properties.");
    static if (F.length > 0)
      other.values[0] >> this[0];
    static if (F.length > 1)
      other.values[1] >> this[1];
    static if (F.length > 2)
      other.values[2] >> this[2];
    static if (F.length > 3)
      other.values[3] >> this[3];
    return 0;
  }*/

  static if (is(Target:E[], E)) { 
    auto opIndex(size_t index)
    {
      return refer(ownerInfo, &((*property)[index]));
    }
  }

  template opDispatch(string name)
    {
        /*static if (is(typeof(__traits(getMember, a, name)) == function))
        {
            // non template function
            auto ref opDispatch(this X, Args...)(auto ref Args args) { return mixin("property."~name~"(args)"); }
        }
        else static if (is(typeof({ enum x = mixin("property."~name); })))
        {
            // built-in type field, manifest constant, and static non-mutable field
            enum opDispatch = mixin("property."~name);
        }
        else */static if (is(typeof(mixin("property."~name))) || __traits(getOverloads, property, name).length != 0)
        {
            // field or property function

            @property auto ref opDispatch(this X)() { return refer(ownerInfo, &mixin("property."~name)); }
            //@property auto ref opDispatch(this X, V)(auto ref V v) { return mixin("property."~name~" = v"); }
        }
    }
}

unittest {
  Value!float A;
  Value!float B;
  auto a = A * 0.5;
  auto b = a + B;
  static assert(is(typeof(A + B)));
  A + B * 0.5;
  A * 0.5 + B;
  A * 0.5 + B * 0.5;  
}


auto refer(O, T)(O* owner, T* target) {
  UGenInfo *info = &UGenRegistry.register(owner);
  return Slot!(T)(info, target);
}

auto refer(O : UGenInfo, T)(O* info, T* target) {
  return Slot!(T)(info, target);
}


mixin template UGEN(Impl) {
public:
  ~this() {
    UGenRegistry.deregister(&this);
  }

  template opDispatch(string name : "isEndPoint") {
    static enum opDispatch = false;
  }

  template opDispatch(string name) if (name[0] != '_' && is(typeof(mixin("this._"~name)))) {
    static if (name[0] != '_' && is(typeof(mixin("this._"~name))))// || __traits(getOverloads, this, "_" ~ name).length != 0)
    {
      @property auto ref opDispatch(this X)() { 
        return refer(&this, &mixin("this._"~name));        
      }
    }
  }

  auto ref opBinary(string op:">>", P)(auto ref P other) if (hasOutput!Impl)
  {
    //pragma(inline, true);
    return pipe(this, other);
  }

  auto ref opBinaryRight(string op:">>", P)(auto ref P other) if (hasInput!Impl)
  {
    //pragma(inline, true);
    return pipe(other, this);
  }

  //mixin Operators;
  auto ref opBinary(string op, R)(auto ref R r) if (op != ">>") {
    return binary!op(this, r);
  }
  auto ref opBinaryRight(string op, R)(auto ref R r) if (op != ">>") {
    return binary!op(r, this);
  }
}

struct Unary(string op, A) {
  A a;

  @property
  auto eval(ulong sampleIndex) { 
    static if (is(typeof(&a.eval))) {
      return mixin(op ~ "a.eval(sampleIndex)");
    }
    else {
      pragma(msg, op, A, is(typeof(&a.eval)));
      static assert(false);
    }
  }

  mixin Operators!();
}


struct Binary(string op, A, B) {
  A a;
  B b;

  @property
  auto eval(ulong sampleIndex) { 
    static if (is(typeof(&a.eval)) && is(typeof(&b.eval))) {
      return mixin("a.eval(sampleIndex)"~op~"b.eval(sampleIndex)");
    }
    else static if (is(typeof(&a.eval)) ) {
      return mixin("a.eval(sampleIndex)"~op~"b");
    }
    else static if (is(typeof(&b.eval))) {
      return mixin("a"~op~"b.eval(sampleIndex)");
    }
    else {
      pragma(msg, A, op ,B, is(typeof(&a.eval)), is(typeof(&b.eval)));
      static assert(false);
    }
  }

  mixin Operators!();

};

template EvalReturnType(alias a) {
  static if (is(typeof(&a.eval))) {
    alias EvalReturnType = ReturnType!(a.eval);
  }
  else {
    alias EvalReturnType = T;
  }
}

auto maybeEval(Arg)(auto ref Arg arg, ulong sampleIndex) {
  static if (is(typeof(&arg.eval))) {
    return arg.eval(sampleIndex);
  }
  else {
    return arg;
  }
}

struct FuncCall1(alias func, Arg) {
  Arg arg;
  @property
  auto eval(ulong sampleIndex) {
    return func(arg.maybeEval(sampleIndex));
  }
}

struct FuncCall2(alias func, Arg1, Arg2) {
  Arg1 arg1; 
  Arg2 arg2; 

  @property
  auto eval(ulong sampleIndex) {
    return func(arg1.maybeEval(sampleIndex), arg2.maybeEval(sampleIndex));
  }
}

import duck.units, std.traits;

template wrapFunction(alias func) {
  auto ref wrapFunction(Arg)(auto ref Arg arg) {
    static if (hasOutput!Arg) {
      auto a = arg.output;
    } else {
      alias a = arg;
    }
    return FuncCall1!(func, typeof(a))(a);
  }
}

alias hz2 = wrapFunction!(hz);
import duck.ugens;
static this() {

  Mono f;
  hz(2) >> f;
  auto a = hz2(f);
  pragma(msg, "XXXX", typeof(a), typeof(a.eval(0)));
  writefln("XXXX %s", a.eval(0));
};

auto ref funcCall1(alias func, Arg)(auto ref Arg arg) {
  //pragma(msg, "calc: " ~ LHS.stringof ~ " " ~ RHS.stringof);

  static if (hasOutput!LHS) {
    auto a = lhs.output;
  } else {
    alias a = lhs;
  }
  pragma(msg, "func: " ~ typeof(a).stringof);
  return FuncCall1!(func, typeof(a))(a);
}


auto ref unary(string op, LHS)(auto ref LHS lhs) {
    //pragma(msg, "calc: " ~ LHS.stringof ~ " " ~ RHS.stringof);
  
    static if (hasOutput!LHS) {
      auto a = lhs.output;
    } else {
      alias a = lhs;
    }
    pragma(msg, "unary: " ~ op ~ typeof(a).stringof);
    return Unary!(op, typeof(a))(a);
  }

auto ref binary(string op, LHS, RHS)(auto ref LHS lhs, auto ref RHS rhs) {
    //pragma(msg, "calc: " ~ LHS.stringof ~ " " ~ RHS.stringof);
  
    static if (hasOutput!LHS) {
      auto a = lhs.output;
    } else {
      alias a = lhs;
    }
    static if (hasOutput!RHS) {
      auto b = rhs.output;
    } else {
      alias b = rhs;
    }
    pragma(msg, "binary: " ~ typeof(a).stringof ~ " " ~ op ~ " " ~ typeof(b).stringof);
    return Binary!(op, typeof(a), typeof(b))(a, b);
  }


  auto ref pipe(LHS, RHS)(auto ref LHS lhs, auto ref RHS rhs) {
    pragma(inline, true);
    //pragma(msg, "pipe: " ~ LHS.stringof ~ " " ~ RHS.stringof);
    static if (hasInput!RHS) {
      static if (hasOutput!LHS) {
        lhs.output.pipe(rhs.input);
        return rhs;
      } else {
        lhs.pipe(rhs.input);
        return rhs;
      }
    }
    else static if (hasOutput!LHS) {
      return lhs.output.pipe(rhs);
    }
    else static if (is(RHS: Slot!R, R)) {
      static if (is(LHS: Slot!L, L)) {
        Connection expr = new Pipe!(LHS, R) (lhs, rhs.property);
        rhs.ownerInfo.connections ~= expr;
        return rhs;
      }
      else static if (is(typeof(&lhs.eval))) {
        Connection expr = new Pipe!(LHS, R) (lhs, rhs.property);
        rhs.ownerInfo.connections ~= expr;
        return rhs;
      }
      else static if (is(ValueProc!(LHS, R))) {
        ValueProc!(LHS, R).set(lhs, *rhs.property);
        return rhs;
      }
      else static assert(false, "Cannot pipe " ~ LHS.stringof ~ " to slot with type " ~ R.stringof);
    }
    else {
      static assert(false, "Pipe target must be a Slot, not " ~ RHS.stringof);
      //static assert(false, "Cannot pipe " ~ LHS.stringof ~ " to " ~ RHS.stringof);
    }
  }


  unittest {
     Mono a;
     Mono b;
     //10.pipe(a).pipe(b);
     binary!"+"(a,b);
     a.pipe(b);
     (a+2.2).pipe(b);
     //"10".ppe(b);

     writefln("s");
  }