
module duck.runtime.print;

import core.stdc.stdlib : exit;

__gshared bool verbose = false;

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

void print(long i) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%lld", i);
}

void print(int i) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%ld", i);
}

void print(double f) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%lf", f);
}

void print(float f) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%f", f);
}

void print(real f) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%lf", cast(double)f);
}

void print(string s) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%.*s", s.length, s.ptr);
}

void print(const(char)* s) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%s", s);
}

void print(char* s) nothrow {
  import core.stdc.stdio;
  stderr.fprintf("%s", s);
}


void print(float[] s) nothrow {
  print("[");
  foreach(i, f ; s) {
    if (i != 0) print(", ");
    print(f);
  }
  print("]");
}

void print(A...)(A a) nothrow if (A.length > 1) {
  foreach(b; a)
    print(b);
}


void rawWrite3(T)(in T buffer) nothrow
{
    import core.stdc.stdio;
    import core.stdc.stdlib;
    FILE *handle = stdout;

    version(Windows)
    {
        flush(); // before changing translation mode
        immutable fd = ._fileno(handle);
        immutable mode = ._setmode(fd, _O_BINARY);
        version(DIGITAL_MARS_STDIO)
        {
            import core.atomic;

            // @@@BUG@@@ 4243
            immutable info = __fhnd_info[fd];
            atomicOp!"&="(__fhnd_info[fd], ~FHND_TEXT);
        }
    }
    auto result =
        fwrite(&buffer, T.sizeof, 1, handle);
    if (result == result.max) result = 0;
    if (result != 1) {
      print("Wrote ");
      print(result);
      print(" instead of ");
      print(1);
      print(" bytes.\n");
      halt();
    }

    version(Windows) {
      flush();
      version(DIGITAL_MARS_STDIO) {
        __fhnd_info[fd] = info;
      }
      ._setmode(fd, mode);
    }
}

void rawWrite2(T)(in T[] buffer) nothrow
{
    import core.stdc.stdio;
    import core.stdc.stdlib;
    FILE *handle = stdout;

    version(Windows)
    {
        flush(); // before changing translation mode
        immutable fd = ._fileno(handle);
        immutable mode = ._setmode(fd, _O_BINARY);
        version(DIGITAL_MARS_STDIO)
        {
            import core.atomic;

            // @@@BUG@@@ 4243
            immutable info = __fhnd_info[fd];
            atomicOp!"&="(__fhnd_info[fd], ~FHND_TEXT);
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

    version(Windows) {
      flush();
      version(DIGITAL_MARS_STDIO) {
        __fhnd_info[fd] = info;
      }
      ._setmode(fd, mode);
    }
}

inout(char)[] fromStringz(inout(char)* cString) @nogc @system pure nothrow {
    import core.stdc.string : strlen;
    return cString ? cString[0 .. strlen(cString)] : null;
}
