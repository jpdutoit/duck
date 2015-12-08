module duck.compiler.input;

import duck.compiler.lexer, duck.compiler.buffer;

struct Input {
  Buffer buffer;
  string text;
  int index = 0;
  char front;

  this(Buffer buffer) {
    import std.stdio;
    this.buffer = buffer;
    this.text = this.buffer.contents;
    consume(0);
  }

  void consume() {
    if (front < 128) {
      consume(1);
    }
    else {
      import std.uni;
      consume(cast(int)graphemeStride(text[index..$], 0));
    }
  }

  string consume(int howMuch) {
    string a = text[index..index+howMuch];
    index += howMuch;
    front = text[index];
    return a;
  }

  bool consume(char character) {
    if (front == character) {
      consume(1);
      return true;
    }

    return false;
  }

  Token tokenSince(Token.Type type, ref Input input) {
    auto t = Token(type, this.buffer[input.index .. index]);
    import std.stdio;
    return t;
  }

  auto save() {
    Input input;
    input.buffer = buffer;
    input.text = text;
    input.index = index;
    input.front = front;
    return input;
  }
};
