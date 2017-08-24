module duck.compiler;
import std.stdio : writefln, writeln;

import duck.compiler.parser, duck.compiler.ast, duck.compiler.lexer, duck.compiler.visitors, duck.compiler.semantic, duck.compiler.context;
import duck.compiler.dbg;
public import duck.compiler.buffer;
import duck.compiler;
import duck.host;


struct DCode {
  this(string code) {
    this.code = code;
  }
  string code;
  bool opCast() {
    return this.code != null;
  }
}

string prettyName(T)(ref T t) {
  import std.regex;
  if (!t) return "";
  return t.classinfo.name.replaceFirst(regex(r"^.*\."), "");
}
