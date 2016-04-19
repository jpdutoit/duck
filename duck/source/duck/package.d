module duck;

import duck.compiler.context;
import duck.host;
import duck.compiler.buffer;

import std.file : getcwd, isFile, exists;
import std.path : buildPath, dirName, baseName;

class Duck {
  static Context[Buffer] cache;

  static Context contextForString(string code) {
    Buffer buffer = new FileBuffer("", getcwd() ~ "/string", false);
    buffer.contents = code ~ "\0";

    if (buffer in cache) return cache[buffer];

    Context context = new Context(buffer);
    context.packageRoots ~= getcwd();
    context.includePrelude = true;

    cache[buffer] = context;

    return context;
  }

  static Context contextForFile(string filename) {
    import std.stdio;
    if (!filename.exists || !filename.isFile) {
      Context context = new Context();
      context.error("No such file: " ~ filename);
      return context;
    }

    Buffer buffer = new FileBuffer(filename, true);

    if (buffer in cache) return cache[buffer];

    Context context = new Context(buffer);
    context.packageRoots ~= filename.dirName;

    import std.algorithm.searching : startsWith;
    import core.runtime;
    context.includePrelude = !filename.startsWith(buildPath(Runtime.args[0].dirName(), "../lib"));

    cache[buffer] = context;

    return context;
  }
}

unittest {
  Duck.contextForString("string");
}