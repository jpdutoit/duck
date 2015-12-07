module test_case;

import std.string;
import std.stdio;

struct TestOutput {
    string stderr;
    string stdout;
}

struct TestCase {
  string options;
  TestOutput output;

  this(string filename) {
    auto s = readFile(filename);
    options = read(s, "OPTIONS");
    output.stderr = read(s, "OUTPUT");
  }

  string readBlock(string contents, string id) {
    string marker = id ~ ":\n---\n";
    long a = contents.indexOf(marker), b;
    if (a >= 0) {
      b = contents[a+marker.length..$].indexOf("\n---");
      return contents[a+marker.length..a+b+marker.length+1].strip;
    }
    return null;
  }

  string readInline(string contents, string id) {
    string marker = id ~ ":";
    long a = contents.indexOf(marker), b;
    if (a >= 0) {
      b = contents[a+marker.length..$].indexOf("\n");
      return contents[a+marker.length..a+b+marker.length+1].strip;
    }
    return null;
  }

  string read(string contents, string id) {
    string output = readBlock(contents, id);
    if (!output) output = readInline(contents, id);
    return output;
  }

  auto readFile(string filename) {
    import std.exception;
    char[1024*1024] buffer;

    // Read input file
    File src = File(filename, "r");
    auto buf = src.rawRead(buffer);
    src.close();
    return buf.assumeUnique;
  }
}
