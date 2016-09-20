module duck.compiler.dbg.colors;

string green(string input) {
  return "\x1B[32m" ~ input ~ "\x1B[39m";
}

string red(string input) {
  return "\x1B[31m" ~ input ~ "\x1B[39m";
}

string blue(string input) {
  return "\x1B[34m" ~ input ~ "\x1B[39m";
}

string yellow(string input) {
  return "\x1B[33m" ~ input ~ "\x1B[39m";
}
