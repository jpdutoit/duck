module duck.compiler.context;

import std.stdio, std.conv;
import duck.compiler.lexer;
import duck.compiler.buffer;

class Context {
  TempBuffer temp;

  this () {
    temp = new TempBuffer("");
  }

  Token token(Token.Type tokenType, string name) {
    return temp.token(tokenType, name);
  }

  Token temporary() {
    return token(Identifier, "__tmp" ~ (++temporaries).to!string);
  }

  int errors;
  int temporaries = 0;
  /*const(char)[] temporary() {
    return "__tmp" ~ (++temporaries).to!(const(char)[]);
  }*/

  void error(Args...)(Span span, string format, Args args)
  {
    errors++;
    stderr.write(span.toString());
    stderr.write(": Error: ");
    stderr.writefln(format, args);
  }

  void error(Span span, string str) {
    errors++;
    stderr.write(span.toString());
    stderr.write(": Error: ");
    stderr.writeln(str);
  }

};
