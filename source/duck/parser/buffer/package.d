module duck.compiler.buffer;
import duck.compiler.lexer.token;

alias String = const(char)[];

struct LineCol {
  int line;
  int col;
};

abstract class Buffer {
  string name;
  string path;
  this(string name, string path) {
    this.name = name;
    this.path = path;
  }

  LineCol[2] calcLineCol(int start, int end) {
    LineCol[2] r;
    r[0] = calcLineCol(start);
    r[1] = r[0];
    for (int i = start; i < end; ++i) {
      if (contents[i] == '\n') {
        r[1].col = 0;
        r[1].line++;
      }
      r[1].col++;
    }
    return r;
  }

  LineCol calcLineCol(int start) {
    LineCol r;
    r.line = 1;
    r.col = 1;
    for (int i = 0; i < start; ++i) {
      if (contents[i] == '\n') {
        r.col = 0;
        r.line++;
      }
      r.col++;
    }
    return r;
  }
  char[] contents;
};

class FileBuffer : Buffer {
  this(string path) {
    super(path, path);
    this.load();
  }

  void load() {
    import std.stdio;
    char buffer[1024*1024];
    // Read input file
    File src = File(path.idup, "r");
    auto buf = src.rawRead(buffer);
    src.close();

    contents = buf ~ "\0";
  }

  /*override String contents() {
    return content;
  }*/

  /*/String content;*/
};

class TempBuffer : Buffer {
  this(string name) {
    super(name, name);
    contents = "".dup;
    contents.assumeSafeAppend();
  }

  /*override String contents() {
    return content;
  }*/

  Token token(Token.Type type, string name) {
    auto start = cast(int)contents.length;
    contents ~= name;
    return Token(type, this, start, start + cast(int)name.length);
  }

  //char[] content;
};
