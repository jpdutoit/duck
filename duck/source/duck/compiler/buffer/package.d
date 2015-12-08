module duck.compiler.buffer;
import duck.compiler.lexer.token;

public import duck.compiler.buffer.slice : Slice, LineColumn;

abstract class Buffer {
  string name;
  string path;

  this(string name, string path) {
    this.name = name;
    this.path = path;
  }

  final auto opSlice(uint from, uint to) {
    return Slice(this, from, to);
  }
  string contents;
}

class FileBuffer : Buffer {
  this(string path) {
    super(path, path);
    this.load();
  }

  void load() {
    import std.stdio;
    char[1024*1024] buffer;
    // Read input file
    File src = File(path.idup, "r");
    auto buf = src.rawRead(buffer);
    src.close();

    contents = (buf ~ "\0").idup;
  }
};

class TempBuffer : Buffer {
  this(string name) {
    super(name, name);
    contents = "".idup;
    assumeSafeAppend(cast(char[])this.contents);
  }

  Token token(Token.Type type, string name) {
    auto start = cast(int)contents.length;
    contents ~= name;
    return Token(type, this[start .. start + cast(int)name.length]);
  }
};
