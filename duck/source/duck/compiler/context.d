module duck.compiler.context;

import std.stdio, std.conv;
import duck.compiler.lexer;
import duck.compiler.buffer;

class Context {
  this () {
    temp = new TempBuffer("");
  }

  Token token(Token.Type tokenType, string name) {
    return temp.token(tokenType, name);
  }

  Token temporary() {
    return token(Identifier, "__tmp" ~ (++temporaries).to!string);
  }

  string[] packageRoots;

  void error(Args...)(Slice slice, string format, Args args)
  {
    errors++;
    stderr.write(slice.toLocationString());
    stderr.write(": Error: ");
    stderr.writefln(format, args);
  }

  void error(Slice slice, string str) {
    errors++;
    stderr.write(slice.toLocationString());
    stderr.write(": Error: ");
    stderr.writeln(str);
  }

  TempBuffer temp;
  int errors;
  int temporaries;
};
