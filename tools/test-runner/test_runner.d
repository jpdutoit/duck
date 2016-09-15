module test_runner;

import std.file;
import std.stdio;
import std.string;
import core.thread, std.process, std.concurrency;
import core.sys.posix.signal;
import std.exception;
import std.algorithm.searching;

import test_case;

string targetFolder = "tests";
string duckExecutable = "bin/duck-test-ext";
string failCompilation = "not-compilable";
string succeedCompilation = "compilable";
string runnable = "runnable";

bool verbose = false;

string[] specifiedFiles;

struct Proc {
    string filename;
    int result;
    Pid pid;

    this(string filename, string method, string options) {
        this.filename = filename;
        auto command = [duckExecutable, method, this.filename];
        if (options)
          command ~= options.split(" ");
        this.pipes = pipeProcess(command);//, Redirect.stderr);
        this.pid = this.pipes.pid;
        //spawn(&streamReader, this.pid.processID(), this.pipes.stderr().getFP());
    }

    void stop() {
        if (tryWait(pid).terminated)
            return;

        kill(this.pid, SIGKILL);
        result = .wait(this.pid);

        pid = Pid.init;
    }

    string  wait() {
      char[] output;
      assumeSafeAppend(output);
      while (this.pipes.stderr().isOpen()) {
        if (!alive) break;
        auto s = this.pipes.stderr().readln();
        if (s) {
          // Have to ignore lines like the following:
          //2015-12-06 11:26:15.572 duck_temp0[84308:8477413] 11:26:15.572 WARNING:  140: This application, or a library it uses, is using the deprecated Carbon Component Manager for hosting Audio Units. Support for this will be removed in a future release. Also, this makes the host incompatible with version 3 audio units. Please transition to the API's in AudioComponent.h.
          if (s.indexOf("deprecated Carbon Component Manager") >= 0) continue;
          s = s.replace("\033[0;31m", "");
          s = s.replace("\033[0m", "");
          output ~= s;
        }
        //write(s);
      }
      result = .wait(this.pid);
      return output.strip.assumeUnique;
    }

    @property bool alive() {
        return !tryWait(pid).terminated;
    }

    static void streamReader(int pid, FILE* osFile)
    {
        import std.string;
        File input = File.wrapFile(osFile);
        while (!input.eof()) {
            string line = input.readln();

            //stderr.writefln("[%s] %s", pid, line);
            //owner.send(pid, line);
        }
    }

    string output;

    ProcessPipes pipes;
}

auto findFiles(string where) {
  string[] files;
  auto dFiles = dirEntries(targetFolder ~ "/" ~ where, "*.{duck}", SpanMode.depth);
  foreach(d; dFiles) {
    if (specifiedFiles.length == 0 || specifiedFiles.canFind(d.name))
      files ~= d.name;
  }
  return files;
}

auto advance(string s, ref int index, int howMuch) {
  import std.uni;
  int start = index;
  for (int i = 0; i < howMuch; ++i) {
    index += graphemeStride(s, index);
  }
  return s[start..index];
}
void compare(string output, string expected) {
  import std.algorithm.comparison;
  import std.uni;
  import std.array;
  auto ops = levenshteinDistanceAndPath(output, expected)[1];

  int o = 0, e = 0;
  //writeln(output.length, ", ", expected.length, " ", ops.length);
  for (int i = 0; i < ops.length; ++i) {
    int length = 1;
    EditOp current = ops[i];
    while(i+1 < ops.length && ops[i+1] == current) {
      ++length;
      ++i;
    }
    final switch(current) {
      case EditOp.none:
        write("\033[0;30m");
        write(output.advance(o, length));
        expected.advance(e, length);
        write("\033[0m");
        break;
      case EditOp.substitute:
        write("\033[0;34m");
        write(expected.advance(e, length));
        write("\033[0;31m");
        write(output.advance(o, length));
        write("\033[0m");
        break;
      case EditOp.insert:
        write("\033[0;34m");
        write(expected.advance(e, length));
        write("\033[0m");
        break;
      case EditOp.remove:
        write("\033[0;31m");
        write(output.advance(o, length));
        write("\033[0m");
        break;
    }
  }
}

void compareOutput(string output, string expected) {
  /*
  if (output != expected) {
    writeln("Output not as expected: (blue missing, red unexpected)");
  compare(output, expected);
  }
  return;*/
  if (expected) {
    writeln("Expected output:");
    write("\033[0;33m");
    write(expected);
    write("\033[0m");
    if (output != expected && output) {
      writeln("\nActual output:");
    }
  } else {
    if (output != expected && output) {
      writeln("Unexpected output:");
    }
  }
  if (output && output != expected) {
    write("\033[0;33m");
    write(output);
    write("\033[0m");
  }
  //writefln("\033[0;9mstrikethrough\033[0m");
}

int failed;
int total;
int succeeded;

auto test(string file, bool expectProcessSuccess, bool run = false)
{
  total++;
  TestCase testCase = TestCase(file);
  Proc proc = Proc(file, run ? "run" : "check", testCase.options ? "-b " ~ testCase.options : "-b");
  auto output = proc.wait();
  if (output == testCase.output.stderr &&
  ((expectProcessSuccess && proc.result == 0)||(!expectProcessSuccess && proc.result != 0))) {
    succeeded++;
    if (verbose)
      writeln("\033[0;32mOK    ", file, "\033[0m");
  }
  else {
    failed++;
    writeln("\033[0;31mFAIL  ", file, "\033[0m");
    if (!expectProcessSuccess && proc.result <= 0) {
      writeln("Unexpected exit code ", proc.result, ", expected > 0.");
    }
    else if (expectProcessSuccess && proc.result != 0) {
      writeln("Unexpected exit code ", proc.result, ", expected 0.");
    }
    compareOutput(output, testCase.output.stderr);
    writeln();
  }
}

auto testSucceedCompilation() {
  //writefln("****** SUCCEED COMPILATION TESTS ******");
  string[] files = findFiles(succeedCompilation);
  foreach(string file; files) {
    test(file, true);
  }
}

auto testFailCompilation() {
  //writefln("****** FAIL COMPILATION TESTS ******");
  string[] files = findFiles(failCompilation);
  foreach(string file; files) {
    test(file, false);
  }
}

auto testRunnable() {
  //writefln("****** FAIL COMPILATION TESTS ******");
  string[] files = findFiles(runnable);
  foreach(string file; files) {
    test(file, true, true);
  }
}


int main(string[] args) {
  for (int i = 1; i < args.length; ++i) {
    string arg = args[i];
    if (arg == "--executable" || arg == "-e") {
      duckExecutable = args[++i];
    }
    else if (arg == "--verbose" || arg == "-v") {
      verbose = true;
    }
    else if (arg.startsWith("-")) {
      stderr.writeln("Unexpected argument: ", arg);
      return 1;
    }
    else specifiedFiles ~= arg;
  }

  if (verbose) {
    writeln("\n************************************************************************************");
    writeln("* Compilable");
    writeln("************************************************************************************\n");
  }
  testSucceedCompilation();

  if (verbose) {
    writeln("\n************************************************************************************");
    writeln("* Not compilable");
    writeln("************************************************************************************\n");
  }
  testFailCompilation();

  if (verbose) {
    writeln("\n************************************************************************************");
    writeln("* Runnable");
    writeln("************************************************************************************\n");
  }
  testRunnable();

  if (verbose) {
    writeln();
    writeln("************************************************************************************");
    write("* ");
  }

  if (failed > 0) {
    write("\033[0;31m");
  } else {
    write("\033[0;32m");
  }
  write(succeeded, "/", total, " tests succeeded.");
  writeln("\033[0m");
  if (verbose)
    writeln("************************************************************************************");

  return failed;
}
