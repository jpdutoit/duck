module duck.compiler.dbg;

import core.exception;

public import duck.compiler.dbg.colors;
public import duck.compiler.dbg.conv;

import duck.compiler.ast, duck.compiler.types;
import duck.compiler.context;

O enforce(O : Object)(Object o, string file = __FILE__, int line = __LINE__) {
  ASSERT(o, "Expected object to be of type " ~ O.stringof ~ " not null", line, file);
  auto c = cast(O)o;
  if (c is null) {
    import std.format: format;
    if (o !is null) {
      throw __ICE(format("Found %s when expecting %s", prettyName(o), O.stringof), line, file);
    } else {
      throw __ICE(format("Found null when expecting %s", O.stringof), line, file);
    }
  }
  return c;
}

auto __ICE(string message = "", int line = __LINE__, string file = __FILE__) {
  import std.stdio, core.stdc.stdlib;
  stderr.write(file);
  stderr.write("(");
  stderr.write(line);
  stderr.write("): ");
  stderr.write("Internal compiler error: ");
  stderr.writeln(message);
  exit(1);
  return new AssertError(message);
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
