module duck.compiler.buffer.slice;
import duck.compiler.buffer;
import std.exception;

struct LineColumn {
  int line;
  int col;
}

struct Slice {
  Buffer buffer;
  uint start = uint.max;
  uint end = uint.max;

  alias toString this;

  bool opCast(T : bool)() const {
    return start < uint.max && end < uint.max;
  }

  LineColumn getStartLocation() const {
    LineColumn r = LineColumn(1, 1);
    for (int i = 0; i < start; ++i) {
      if (buffer.contents[i] == '\n') {
        r.col = 0;
        r.line++;
      }
      r.col++;
    }
    return r;
  }



  LineColumn[2] getLocation() const {
    LineColumn[2] r = getStartLocation();
    //r[0] = getStart();
    r[1] = r[0];
    for (uint i = start; i < end; ++i) {
      if (buffer.contents[i] == '\n') {
        r[1].col = 0;
        r[1].line++;
      }
      r[1].col++;
    }
    return r;
  }

  Slice opBinary(string op : "+")(Slice other){
    if (buffer != other.buffer) {
      if (cast(FileBuffer)buffer)
        return this;
      else if (cast(FileBuffer)other.buffer)
        return other;
      else return this;
    }
    if (!other) return this;
    if (!this) return other;

    uint aa = start < other.start ? start : other.start;
    uint bb = end > other.end ? end : other.end;
    return Slice(buffer, aa, bb);
  }

  auto lineNumber() const {
    return getStartLocation().line;
  }

  auto toLocationString() const {
    import std.conv;
    LineColumn[2] ab = getLocation();
    LineColumn a = ab[0], b = ab[1];
    if ((a.line == b.line) && (a.col == b.col-1)) {
      return buffer.name ~ "(" ~ a.line.to!string ~ ":" ~ a.col.to!string ~ ")";
    }
    else if ((a.line == b.line)) {
      return buffer.name ~ "(" ~ a.line.to!string ~ ":" ~ a.col.to!string  ~ "-" ~ (b.col-1).to!string ~ ")";
    }
    return buffer.name ~ "(" ~ a.line.to!string ~ ":" ~ a.col.to!string ~ "-" ~ b.line.to!string ~ ":" ~ (b.col-1).to!string ~ ")";
  }

  string toString() const {
    if (!buffer) return "";
    return buffer.contents[start..end].assumeUnique;
  }
}
