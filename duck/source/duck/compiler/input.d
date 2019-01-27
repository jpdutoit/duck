module duck.compiler.input;

import duck.compiler.lexer, duck.compiler.buffer;

struct Input {
  Buffer buffer;
  int line = 1;
  int column = 1;
  int indent = 0;

  string text;
  int index = 0;
  char front;

  this(Buffer buffer) {
    import std.stdio;
    this.buffer = buffer;
    this.text = this.buffer.contents;
    this.front = this.text[0];
  }

  void consume() {
    if (front < 128) {
      switch (front) {
        case '\n':
          line++;
          column = 1;
          indent = 0;
          break;

        case ' ', '\t':
          if (indent + 1 == column)
            ++indent;
          goto default;

        default:
          ++column;
          break;
      }
      ++index;
      front = text[index];
    }
    else {
      import std.uni;
      auto length = cast(int)graphemeStride(text[index..$], 0);
      index += length;
      front = text[index];
      ++column;
    }
  }

  private string consume(int howMuch) {
    string a = text[index..index+howMuch];
    index += howMuch;
    front = text[index];
    return a;
  }

  bool consume(char character) {
    if (front == character) {
      consume();
      return true;
    }

    return false;
  }

  Token tokenSince(Token.Type type, ref Input input) {
    return Token(type, Slice(this.buffer, input.index, index, input.line));
  }

  Slice slice(Slice from, Slice to) {
    if (!from) return Slice();
    return Slice(this.buffer, from.start, to.end, from.line);
  }

  Slice sliceUntil(Slice from, Slice end) {
    if (!from) return Slice();
    return Slice(this.buffer, from.start, end.start, from.line);
  }

  auto save() {
    Input input;
    input.buffer = buffer;
    input.text = text;
    input.index = index;
    input.front = front;
    input.line = line;
    return input;
  }
};
