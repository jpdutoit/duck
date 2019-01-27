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

  string dirname() {
    import std.path: dirName;
    return this.path.dirName;
  }

  string hashString() {
    import std.digest : toHexString;
    size_t hash = this.hashOf;
    ubyte[8] result = (cast(ubyte*) &hash)[0..8];
    return toHexString(result[0..8]).dup;
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
  
  string contents;
  size_t _hash;
}

class FileBuffer : Buffer
{
  this(string path) {
    super(path, path);
    this.load();
  }

  this(string path, string contents) {
    super(name, path);
    this.contents = contents;
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
