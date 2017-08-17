module duck.compiler.backend.backend;
import duck.host : Process;
import duck.compiler.context : Context;
import std.stdio : File;

struct SourceFile {
  string filename;
  string sourceCode;

  void save() {
    File dst = File(filename, "w");
    dst.rawWrite(sourceCode);
    dst.close();
  }
}

interface SourceToSourceCompiler {
  SourceFile[] transpile();
}

interface SourceToBinaryCompiler {
  Executable compile(string[] engines = []);
}

abstract class Backend {
  Context context;

  this(Context context) {
    this.context = context;
  }

  SourceToBinaryCompiler compiler() {
    return cast(SourceToBinaryCompiler)this;
  }

  SourceToSourceCompiler transpiler() {
    return cast(SourceToSourceCompiler)this;
  }
}

struct Executable {
    string filename;

    this(string filename) {
        this.filename = filename;
    }

    Process execute() {
        return Process(this.filename);
    }

    bool opCast(){
      return filename != null && filename.length > 0;
    }
}
