module duck.runtime;
public import duck.runtime.scheduler;
public import duck.runtime.model;
public import duck.runtime.entry;

public import core.math;
__gshared bool verbose = false;

//extern(C) double sin ( double x );
//extern(C) double cos ( double x );
extern(C) float floorf ( float );
//extern(C)
//float fabs ( float f ) {  return f >= 0 ? f : -f;};
extern(C) float roundf ( float );
extern(C) float powf (float, float );
alias abs = fabs;

auto haltOnException(T)(lazy T t) nothrow {
  try {
    return t();
  }
  catch(Exception e) {
    _halt(e.msg);
    assert(0);
  }
}
void log(lazy string s) nothrow {
  if (verbose) {
    import duck.runtime;
    haltOnException(print(s));
  }
}

void warn(lazy string s) nothrow {
  try {
    import duck.runtime;
    print(s);
    //stderr.writeln(s);
  }
  catch (Exception e) {
    exit(1);
  }
}

void _halt(string s) nothrow {
  warn(s);
  exit(1);
}

void halt() nothrow {
  exit(1);
}
void halt(lazy string s) nothrow {
  _halt(haltOnException(s));
}


void print(long i) {
  import core.stdc.stdio;
  stderr.fprintf("%lld", i);
}

void print(int i) {
  import core.stdc.stdio;
  stderr.fprintf("%ld", i);
}

void print(double f) {
  import core.stdc.stdio;
  stderr.fprintf("%lf", f);
}

void print(float f) {
  import core.stdc.stdio;
  stderr.fprintf("%f", f);
}

void print(real f) {
  import core.stdc.stdio;
  stderr.fprintf("%lf", cast(double)f);
}

void print(string s) {
  import core.stdc.stdio;
  stderr.fprintf("%.*s", s.length, s.ptr);
}

void print(const(char)* s) {
  import core.stdc.stdio;
  stderr.fprintf("%s", s);
}

void print(char* s) {
  import core.stdc.stdio;
  stderr.fprintf("%s", s);
}


void print(float[] s) {
  print("[");
  foreach(i, f ; s) {
    if (i != 0) print(", ");
    print(f);
  }
  print("]");
}

void print(A...)(A a) if (A.length > 1) {
  foreach(b; a)
    print(b);
}

void rawWrite2(T)(in T[] buffer)
{
    import core.stdc.stdio;
    import core.stdc.stdlib;
    FILE *handle = stdout;

    version(Windows)
    {
        flush(); // before changing translation mode
        immutable fd = ._fileno(handle);
        immutable mode = ._setmode(fd, _O_BINARY);
        scope(exit) ._setmode(fd, mode);
        version(DIGITAL_MARS_STDIO)
        {
            import core.atomic;

            // @@@BUG@@@ 4243
            immutable info = __fhnd_info[fd];
            atomicOp!"&="(__fhnd_info[fd], ~FHND_TEXT);
            scope(exit) __fhnd_info[fd] = info;
        }
        scope(exit) flush(); // before restoring translation mode
    }
    auto result =
        fwrite(buffer.ptr, T.sizeof, buffer.length, handle);
    if (result == result.max) result = 0;
    if (result != buffer.length) {
      print("Wrote ");
      print(result);
      print(" instead of ");
      print(buffer.length);
      print(" bytes.\n");
      halt();
    }
    /*errnoEnforce(result == buffer.length,
            text("Wrote ", result, " instead of ", buffer.length,
                    " objects of type ", T.stringof, " to file `",
                    _name, "'"));*/
}

inout(char)[] fromStringz(inout(char)* cString) @nogc @system pure nothrow {
    import core.stdc.string : strlen;
    return cString ? cString[0 .. strlen(cString)] : null;
}

public import duck.runtime.global;

version(USE_PORT_AUDIO) {
  public import duck.plugin.portaudio;
}
