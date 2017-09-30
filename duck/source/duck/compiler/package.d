module duck.compiler;
import std.stdio : writefln, writeln;

public import duck.compiler.ast;
public import duck.compiler.context;
public import duck.compiler.lexer;
public import duck.compiler.parser;
public import duck.compiler.buffer;
public import duck.compiler.dbg;
public import duck.compiler.types;
public import duck.compiler.scopes;
public import duck.compiler.semantic.errors;


struct DCode {
  this(string code) {
    this.code = code;
  }
  string code;
  bool opCast() {
    return this.code != null;
  }
}
