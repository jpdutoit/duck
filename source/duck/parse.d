module duck.parse;

import std.string, std.stdio, std.array;

int checkit(const(char)[] input) {
  import duck.compiler;
  return duck.compiler.check(input);
}

const(char)[] compile(const(char)[] input) {
  import duck.compiler;
  return duck.compiler.compile(input);
}
