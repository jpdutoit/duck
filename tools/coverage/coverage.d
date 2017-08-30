module coverage;

import std.stdio;
import std.string;
import std.file;
import std.array;
import std.algorithm;
import std.regex;
import std.conv : to;

string templateFolder = ".";

auto TemplateRegex = regex("\\$\\{([a-zA-Z][a-zA-Z0-9]*)\\}");

struct Template {
  string contents;

  this(string filename) {
    char[1024*1024] buffer;
    // Read input file
    File src = File(filename, "r");
    auto buf = src.rawRead(buffer).idup;
    src.close();
    this.contents = buf;
  }

  string expand(string[string] data) {
    data["$"] = "$";
    string find(Captures!(string) m) {
      return m[1] in data ? data[m[1]] : "";
    }
    auto result = replaceAll!(find)(contents, TemplateRegex);
    //writeln(data, " ", contents, " ", result);
    return result;
  }
}

auto findFiles(string where) {
  string[] files;
  auto dFiles = dirEntries(where, "*.{lst}", SpanMode.depth);
  foreach(d; dFiles) {
    if (d.name.indexOf("-dbg-") >= 0) continue;
    files ~= d.name;
  }
  return files;
}

int main(string[] args) {
  for (int i = 1; i < args.length; ++i) {
    string arg = args[i];
    if (arg == "--template" || arg == "-t") {
      templateFolder = args[++i];
    }
    else if (arg.startsWith("-")) {
      stderr.writeln("Unexpected argument: ", arg);
      return 1;
    }
    else {
      stderr.writeln("Unexpected argument: ", arg);
      return 1;
    }
  }

  // Load templates
  Template indexFileTemplate = Template(templateFolder ~ "/index-file.html");
  Template indexLineTemplate = Template(templateFolder ~ "/index-line.html");
  Template sourceFileTemplate = Template(templateFolder ~ "/source-file.html");
  Template sourceLineTemplate = Template(templateFolder ~ "/source-line.html");

  //  Find all coverage files, and sort them
  auto files = findFiles("coverage");

  files.multiSort!(
    (string x, string y) => x.count("-") < y.count("-"),
    (string x, string y) => x < y
    );

  Appender!string indexLines;

  int totalCovered = 0, totalCoverable = 0, totalLines = 0;
  foreach(inputFilename; files) {
    // Exclude debug file
    if (inputFilename.indexOf("parser-dbg.lst") >= 0) continue;

    int line = 0, coverable = 0, covered = 0;

    auto inputLines = File(inputFilename).byLine(KeepTerminator.yes);
    Appender!string coverageLines = Appender!string();
    inputLines
      .map!((s) {
        line++;
        auto pipe = s.indexOf("|");
        if (pipe > 0) {
          string cov = "";
          int count = 0;

          auto coveragePart = s[0..pipe].stripLeft;
          if (coveragePart.length > 0) {
            count = coveragePart.to!int;
            if (count > 0) covered++;
            cov = count.to!string;
            coverable++;
          }

          auto linestr = s[pipe+1..$];
          auto undented = linestr.stripLeft;
          auto indent = linestr[0..linestr.length-undented.length];
          return sourceLineTemplate.expand([
            "CLASS": cov.length ? (count > 0 ? "non-zero": "zero") : "not-code",
            "COV": cov,
            "INDENT": indent.to!string,
            "LINE": undented.to!string,
            "LINENUMBER": line.to!string
          ]);
        } else {
          return "";
        }
      })
      .copy(&coverageLines);

      int percentage = cast(int)(coverable ? cast(float)covered / coverable * 100 : 100);

      auto name = inputFilename.split("/")[1].replace("-", "/").replace(".lst", ".d");

      {
        // Write source coverage file
        auto coverageFile = File(inputFilename.replace(".lst", ".html"), "w");
        auto coverage = coverageFile.lockingTextWriter();
        coverage.put(sourceFileTemplate.expand([
          "FILENAME": name,
          "LINES": coverageLines.data
        ]));
      }

      {
        // Add coverage summary line to index
        string cls;
        if (percentage > 95 || (coverable - covered) < 6) cls = "good";
        else if (percentage > 80 || (coverable - covered) < 20) cls = "ok";
        else cls = "bad";

        indexLines.put(indexLineTemplate.expand([
          "CLASS": cls,
          "LINK": "../" ~ inputFilename.replace(".lst", ".html"),
          "LINKTITLE": name,
          "COVERED": covered.to!string,
          "COVERABLE": coverable.to!string,
          "TOTAL": line.to!string,
          "PERCENTAGE": percentage.to!string,
        ]));
      }

      totalCovered += covered;
      totalCoverable += coverable;
      totalLines += line;
  }

  {
    // Add totals line to index
    int percentage = cast(int)(totalCoverable ? cast(float)totalCovered / totalCoverable * 100 : 100);
    indexLines.put(indexLineTemplate.expand([
      "COVERED": totalCovered.to!string,
      "COVERABLE": totalCoverable.to!string,
      "TOTAL": totalLines.to!string,
      "PERCENTAGE": percentage.to!string,
    ]));
  }

  {
    // Write the index files
    auto indexFile = File("coverage/index.html", "w");
    auto index = indexFile.lockingTextWriter;
    index.put(indexFileTemplate.expand([
      "LINES": indexLines.data
    ]));
  }

  return 0;
}
