module duck.compiler.dbg;

public import duck.compiler.dbg.colors;
public import duck.compiler.dbg.conv;

import duck.compiler.ast, duck.compiler.types;

auto __ICE(string message = "", int line = __LINE__, string file = __FILE__) {
  import core.exception;
  import std.conv;
  import std.stdio;
  auto msg = "Internal compiler error: " ~ message ~ " at " ~ file ~ "(" ~ line.to!string ~ ") ";
  stderr.writeln(msg);
  //asm {hlt;}
  return new AssertError(msg);
}

void ASSERT(T)(T value, lazy string message, int line = __LINE__, string file = __FILE__) {
  if (!value) {
    throw __ICE(message, line, file);
  }
}

string describe(const Type type) {
  return type ? type.mangled() : "?";
}

string prettyName(T)(ref T t) {
  import std.regex;
  if (!t) return "";
  return t.classinfo.name.replaceFirst(regex(r"^.*\."), "");
}

struct TreeLogger {
  enum string PAD = "                                                                                                                                           ";
  int logDepth;
  static string logPadding(int __depth) { return PAD[0..__depth*4]; }
  void _log(string what) {
    import std.stdio : write, writeln, stderr;
    stderr.write(logPadding(logDepth), what);
  }
}

__gshared TreeLogger _logger;
void logIndent() { _logger.logDepth++; }
void logOutdent() { _logger.logDepth--; }
void log(T...)(string what, T t) {
  import std.stdio : write, writeln, stderr;
  _logger._log(what);
  foreach(tt; t) stderr.write(" ", tt);
  stderr.writeln();
}
