module duck.compiler.lexer.token;

import duck.compiler.buffer;

private import std.typetuple: staticIndexOf;
private import std.meta : AliasSeq;

alias String = const(char)[];

/*
  struct Type {
    this(string name) {
      this.name = name;
      this.id = name.hashOf();
    }
    string name;
    size_t id;

    alias id this;
  };
*/

struct Pos {
  this(int l, int c) {
    line = l; col = c;
  }
  int line;
  int col;
  bool opCast(T : bool)() {
    return line != 0;
  }
  int opCmp(Pos other) {
    if (line != other.line) return line - other.line;
    return col - other.col;
  }
}


struct Span {
  this(Buffer buffer, Pos c, Pos d) {
    this.buffer = buffer;
    a = c;
    b = d;
  }
  Buffer buffer;
  Pos a, b;

  bool opCast(T : bool)() {
    return a && b;
  }

  Span opBinary(string op : "+")(Span other) {
    if (buffer != other.buffer) {
      if (cast(FileBuffer)buffer)
        return this;
      else if (cast(FileBuffer)other.buffer)
        return other;
      else return this;
    }
    if (!other) return this;
    if (!this) return other;
    Pos aa, bb;
    aa = a < other.a ? a : other.a;
    bb = b > other.b ? b : other.b;
    return Span(buffer, aa, bb);
  }

  auto toString() {
    import std.conv;
    if ((a.line == b.line) && (a.col == b.col-1)) {
      return buffer.name ~ "(" ~ a.line.to!string ~ ":" ~ a.col.to!string ~ ")";
    }
    else if ((a.line == b.line)) {
      return buffer.name ~ "(" ~ a.line.to!string ~ ":" ~ a.col.to!string  ~ "-" ~ (b.col-1).to!string ~ ")";
    }
    return buffer.name ~ "(" ~ a.line.to!string ~ ":" ~ a.col.to!string ~ "-" ~ b.line.to!string ~ ":" ~ (b.col-1).to!string ~ ")";
  }
};


struct Token {
  alias Type = ubyte;

  Buffer buffer;
  Type type;

  alias value this;

  @property String value() {
    if (!buffer) return "";
    return buffer.contents[start..end];
  }

  this(Type type, Buffer buffer, int start = 0, int end = 0) {
    //import core.exception;
    //if (buffer is null) throw new AssertError("ff");
    this.type = type;
    this.buffer = buffer;
    this.start = start;
    this.end = end;
  }

  bool opCast(T : bool)() const {
    return type != 0;
  }

  Span span() {
    String buf = buffer.contents;

    if (start == 0 && end == buf.length)
      return Span(buffer, Pos(0, 0), Pos(0, 0));

    int line = 1;
    int col = 1;
    for (int i = 0; i < start; ++i) {
      if (buf[i] == '\n') {
        col = 0;
        line++;
      }
      col++;
    }
    int line2 = line, col2 = col;

    for (int i = start; i < end; ++i) {
      if (buf[i] == '\n') {
        col2 = 0;
        line2++;
      }
      col2++;
    }
    return Span(buffer, Pos(line, col), Pos(line2, col2));
  }


  private:
    int start;
    int end;
};
