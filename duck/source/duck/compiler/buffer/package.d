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

  size_t hashOf() {
    if (_hash) return _hash;

    import std.digest.md;
    MD5 hash;
    hash.start();
    hash.put(cast(ubyte[])name);
    hash.put(cast(ubyte[])path);
    hash.put(cast(ubyte[])contents);
    hash.put(cast(ubyte)0);
    ubyte[16] result = hash.finish();
    return _hash = *(cast(size_t*)result.ptr);
  }

  override
  bool opEquals(Object object) {
    Buffer buffer = cast(Buffer)object;
    if (!buffer) return false;
    return buffer.hashOf == hashOf;
  }

  final auto opSlice(uint from, uint to) {
    return Slice(this, from, to);
  }
  string contents;
  size_t _hash;
}

class FileBuffer : Buffer 
{
  
  this(string path, bool loadIt = true) {
    super(path, path);
    if (loadIt)
      this.load();
  }
  this(string name, string path, bool loadIt = true) {
    super(name, path);
    if (loadIt)
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
