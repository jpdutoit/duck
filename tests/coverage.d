module coverage;

import std.stdio;
import std.string;
import std.file;
import std.array;
import std.algorithm;
import std.exception;

auto findFiles(string where) {
  string[] files;
  auto dFiles = dirEntries(where, "*.{lst}", SpanMode.depth);
  foreach(d; dFiles) {
    files ~= d.name;
  }
  return files;
}

int main() {
  auto cssFile = File("coverage/index.css", "w");
  auto css = cssFile.lockingTextWriter;
  css.put("""CSS
    .lines * {
      line-height: 80%;
    }
    .zero {
      color: red;
    }
    .not-code {
      color: gray;
      font-size: 60%;
    }
    .non-zero {
      font-size: 60%;
    }

    .good {
      background-color: #77DD77;
    }

    .ok {
      background-color: #FFB347;
    }

    .bad {
      background-color: #FF6961;
    }

    table {
      border-collapse: collapse;
    }
    body {
      //width: 800px;

    }

    table.index {
      margin:0 auto;
      color: black;
      line-height: 140%;
    }

    table.index a {
      color: black;
      text-decoration: none;
    }

    .index td, .index th {
      padding: 0 10px;
    }

    .index td:nth-child(1) {
      max-width: 100%;
    }

    .index td:not(:first-child), .index th:not(:first-child) {
      border-left: 1px solid #000;
      width: 60px;
      text-align: center;
    }

    .index tr:last-child {
      border-top: 1px solid #000;
    }

    .index td:first-child, .index th:first-child {
      text-align: left;
    }

    .index th {
      text-align: left;
      font-size:70%;
      text-transform: uppercase;
      border-bottom: 1px solid #000;
    }

    .lines td:nth-child(1) {
      padding-left: 4px;
      width:60px;
      text-align:left;
      border-right: 1px solid #000;
    }
    .lines td:nth-child(2) {
      border-right: 1px solid #000;
      width:60px;
      padding-right:10px;
      text-align:right;
    }
    .lines td:nth-child(3) {
      padding-left: 4px;
    }
  CSS""");

  auto files = findFiles("coverage");
  files.multiSort!(
    (string x, string y) => cast(int)x.count("-") < cast(int)y.count("-"),
    (string x, string y) => x < y
    );
  auto indexFile = File("coverage/index.html", "w");
  auto index = indexFile.lockingTextWriter;
  index.put("<html><head><meta charset=\"utf-8\"><link rel=\"stylesheet\" type=\"text/css\" href=\"index.css\"></head><body><table class=\"index\">");
  index.put(format("<tr><th>Filename</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th></tr>", "Covered Lines", "Coverable Lines", "Total Lines", "%"));

  int totalCovered = 0, totalCoverable = 0, totalLines = 0;
  foreach(inputFilename; files) {
    // Exclude debug file
    if (inputFilename.indexOf("parser-dbg.lst") >= 0) continue;

    auto oFile = File(inputFilename.replace(".lst", ".html"), "w");
    auto output = oFile.lockingTextWriter();
    auto input = File(inputFilename).byLine(KeepTerminator.yes);
    output.put("<html><head><meta charset=\"utf-8\"><link rel=\"stylesheet\" type=\"text/css\" href=\"index.css\"></head><body><table class=\"lines\">");

    auto name = inputFilename.split("/")[1].replace("-", "/").replace(".lst", ".d");
    output.put(format("<tr><th class=\"title\" colspan=\"3\">%s</th></tr>", name));
    output.put("<tr><th>count</th><th>line</th><th></th></tr>\n");
    int line = 0;
    int coverable = 0;
    int covered = 0;
    input
      .map!((s) {
        line++;
        auto pipe = s.indexOf("|");
        if (pipe > 0) {
          import std.conv : to;
          auto cs = s[0..pipe].stripLeft;
          if (s.indexOf("__ICE") >= 0) {
            cs = null;
          }
          if (cs.length > 0) {
            int count = s[0..pipe].stripLeft.to!int;
            if (count > 0) covered++;
            coverable++;
            return format("<tr class=\"%s\"><td>%s</td><td>%s</td><td><pre>%s</pre></td></tr>", count > 0 ? "non-zero":"zero", count, line, s[pipe+1..$]);
          } else {
            return format("<tr class=\"not-code\"><td>%s</td><td>%s</td><td><pre>%s</pre></td></tr>", "", line, s[pipe+1..$]);
          }
        } else {
          return "";
          //return format("<tr><td colspan=\"3\">%s</td></tr>", s);
        }
      })
      .copy(output);

      int percentage = cast(int)(coverable ? cast(float)covered / coverable * 100 : 100);
      string cls;
      if (percentage > 95 || (coverable - covered) < 6) cls = "good";
      else if (percentage > 80 || (coverable - covered) < 20) cls = "ok";
      else cls = "bad";
      index.put(format("<tr class=\"%s\"><td><a href=\"%s\">%s</a></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", cls, "../" ~ inputFilename.replace(".lst", ".html"), name, covered, coverable, line, percentage));
      output.put("</table></body><html>");

      totalCovered += covered;
      totalCoverable += coverable;
      totalLines += line;
  }
  int percentage = cast(int)(totalCoverable ? cast(float)totalCovered / totalCoverable * 100 : 100);
  index.put(format("<tr><td></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", totalCovered, totalCoverable, totalLines, percentage));
  index.put("</table></body><html>");

  return 0;
}
