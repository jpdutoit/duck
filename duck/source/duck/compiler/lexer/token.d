module duck.compiler.lexer.token;

import duck.compiler.buffer;

private import std.typetuple: staticIndexOf;
private import std.meta : AliasSeq;
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

struct Token {
  alias Type = ubyte;

  Type type;
  Slice slice;

  alias slice this;

  @property
  string value() const {
    if (!slice) return "";
    return slice.toString();
  }

  bool opCast(T : bool)() const {
    return type != 0;
  }
};
