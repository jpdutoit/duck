module duck.compiler;
import std.stdio : writefln, writeln;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.lexer, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
public import duck.compiler.context;
public import duck.compiler.buffer;
public import duck.compiler.dbg;

struct DCode {
  this(string code) {
    this.code = code;
  }
  string code;
  bool opCast() {
    return this.code != null;
  }
}
