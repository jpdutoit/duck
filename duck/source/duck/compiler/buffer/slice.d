module duck.compiler.buffer.slice;
import duck.compiler.buffer;
import std.exception;

struct LineColumn {
  int line;
  int col;
}

struct Slice {
  Buffer buffer;
  union {
    struct {
      string _value = null;
    }
    struct {
      uint start;
      uint end;
    }
  }
  uint line;

  this(Buffer buffer, uint start, uint end, uint line) {
    this.buffer = buffer;
    this.start = start;
    this.end = end;
    this.line = line;
  }

  this(string value) {
    this.buffer = null;
    this._value = value;
    this.line = 1;
  }

  alias toString this;
  alias value = toString;

  bool opCast(T : bool)() const {
    return buffer ? start < uint.max && end < uint.max : false;
  }

  int indent() const {
    int indent = 0;
    if (!(cast(bool)this)) return indent;
    for (int i = start - 1; i >= 0; --i) {
      if (buffer.contents[i] == '\n') {
        return indent;
      }
      if (buffer.contents[i] == ' ' || buffer.contents[i] == '\t') {
        indent++;
        continue;
      }
      indent = 0;
    }
    return indent;
  }

  int column() const {
    int column = 1;
    if (!(cast(bool)this)) return column;
    for (int i = start - 1; i >= 0; --i) {
      if (buffer.contents[i] == '\n') {
        return column;
      }
      column++;
    }
    return column;
  }

  LineColumn getStartLocation() const {
    return LineColumn(line, column);
  }

  LineColumn[2] getLocation() const {
    LineColumn[2] r = getStartLocation();
    if (!(cast(bool)this)) return r;
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

  void opOpAssign(string op : "+") (Slice other) {
    this = this + other;
  }

  Slice opSlice(uint x, uint y) {
    if (!buffer)
      return Slice(_value[x..y]);
    int line = this.line;
    for (int i = start; i <= start+x; ++i)
      if (buffer.contents[i] == '\n') ++line;
    return Slice(buffer, start + x, start + y, line);
  }

  @property int opDollar(size_t dim : 0)() {
    return buffer !is null ? end-start : cast(int)_value.length;
  }

  Slice opBinary(string op : "+")(Slice other){
    if (buffer != other.buffer) {
      if (cast(FileBuffer)buffer)
        return this;
      else if (cast(FileBuffer)other.buffer)
        return other;
    }
    if (!other) return this;
    if (!this) return other;

    uint aa = start < other.start ? start : other.start;
    uint bb = end > other.end ? end : other.end;
    return Slice(buffer, aa, bb, start < other.start ? line : other.line);
  }

  auto lineNumber() const {
    return this.line;
  }

  auto toLocationString() const {
    import std.conv;
    if (!buffer) return "";
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
    if (!buffer) return _value;
    return buffer.contents[start..end].assumeUnique;
  }
}
