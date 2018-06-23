module duck.compiler.backend.d.appender;

import duck.compiler.ast;
import duck.util.stack;
import std.array: replace, Appender, join;
import std.algorithm: map;
import std.conv: to;
import std.traits: isBasicType;

struct DAppender(Generator) {

  private int depth = 0;
  private auto childCount = Stack!int();
  Appender!string output;
  Generator *generator;

  this(Generator *generator) {
    this.generator = generator;
    childCount.push(0);
  }

  void block(T)(scope T block) {
    blockStart();
    put(block);
    blockEnd();
  }

  void blockStart() {
    childCount.push(0);
    put("{");
    indent();
  }

  void blockEnd() {
    outdent();
    newline();
    childCount.pop();
    put("}");
  }

  void structDecl(T)(string name, scope T block) {
    newline();
    newline();
    put("struct ");
    put(name);
    put(" ");
    blockStart();
    put(block);
    blockEnd();
  }

  void functionDecl(T)(scope T returnType, string name) {
    childCount.push(0);
    newline();
    newline();
    put(returnType);
    put(" ");
    put(name);
    put("(");
  }

  void functionDecl(T)(scope T returnType, string attributes, string name) {
    childCount.push(0);
    newline();
    newline();
    put(attributes);
    put(" ");
    put(returnType);
    put(" ");
    put(name);
    put("(");
  }

  void functionArgument(T)(scope T type, string name) {
    if (childCount.top > 0) {
      put(", ");
    }
    put(type);
    put(" ");
    put(name);
    childCount.top += 1;
  }

  void functionBody(T)(scope T block) {
    put(") nothrow ");
    childCount.pop();
    blockStart();
    put(block);
    blockEnd();
  }

  void statement(T...)(T statement) {
    newline();
    put(statement);
    childCount.top += 1;
  }

  void expression(T...)(T expression) {
    output.put("(");
    put(expression);
    output.put(")");
  }

  void ifStatement(A, B)(scope A condition, scope B trueBody) {
    newline();
    output.put("if (");
    put(condition);
    output.put(") ");
    blockStart();
    put(trueBody);
    blockEnd();
  }

  void elseStatement(B)(scope B elseBody) {
    if (elseBody is null) return;
    output.put(" else ");
    blockStart();
    put(elseBody);
    blockEnd();
  }

  static string PAD = "\n                                                                                                                         ";
  void put(T...)(T items) if (T.length > 1) {
    foreach(item; items) {
      put(item);
    }
  }

  void put(string s) {
    output.put(s.replace("\n", PAD[0..depth*2+1]));
  }

  void put(T)(T s) if (isBasicType!T && !is(T:string)) {
    output.put(s.to!string);
  }

  void put(bool b) {
    output.put(b ? "true" : "false");
  }

  void put(void delegate() dg) {
    dg();
  }

  void put(Node e) {
    generator.accept(e);
  }

  void put(Expr[] e) {
    foreach (i, expr; e) {
      if (i != 0) put(", ");
      generator.accept(expr);
    }
  }

  void newline() {
    put("\n");
    putLineInfo();
  }

  void line(int number, string buffer) {
    currentLineNumber = number;
    currentLineBuffer = buffer;
    //putLineInfo();
  }

  void putLineInfo() {
    if (currentLineNumber == 0) return;
    debug(CodeGen) { put("/*"); } else { put ("#"); }
    put("line ");
    put(currentLineNumber);
    put(" \"");
    put(currentLineBuffer);
    put("\" \n");
    debug(CodeGen) { put("*/"); }
  }

  string currentLineBuffer;
  int currentLineNumber;

  void indent() { depth++; }
  void outdent() { depth--; }

  @property auto data() { return output.data; }
}
