module duck.util.json;

import duck.util.stack;
import std.array: replace, Appender, join;
import std.algorithm: map;
import std.conv: to;
import std.traits: isBasicType;
import std.variant: Algebraic;

alias JsonKey = Algebraic!(int,string);

struct JsonAppender {
  bool prettyPrint = true;

  private int depth = 0;
  auto pointerParts = Stack!JsonKey();
  private auto childCount = Stack!int();
  Appender!string output;

  this(bool prettyPrint) {
    this.prettyPrint = prettyPrint;
  }

  void dictStart() {
    childCount.push(0);
    put("{");
    indent();
  }

  void dictEnd() {
    outdent();
    if (childCount.top > 0) {
      pointerParts.pop();
      newline();
    }
    childCount.pop();
    put("}");
  }

  void dictField(string name)  {
    if (childCount.top > 0) {
      pointerParts.pop();
      comma();
    }
    pointerParts.push(JsonKey(name));
    newline();
    put("\"");
    put(name);
    if (prettyPrint) {
      put("\": ");
    } else {
      put("\":");
    }
    childCount.top += 1;
  }

  void dictField(T)(string name, T value) if (isBasicType!T){
    dictField(name);
    output.put(value.to!string);
  }

  void dictField(string name, string value) {
    dictField(name);
    output.put("\"");
    output.put(value);
    output.put("\"");
  }

  void arrayStart() {
    childCount.push(0);
    put("[");
    indent();
  }

  void arrayItem() {
    if (childCount.top > 0) {
      pointerParts.pop();
      comma();
    }
    pointerParts.push(JsonKey(childCount.top));
    childCount.top += 1;
  }

  void arrayEnd() {
    outdent();
    if (childCount.top > 0) {
      pointerParts.pop();
      newline();
    }
    childCount.pop();
    put("]");
  }

  static string PAD = "\n                                                                                                                         ";
  void put(string s) {
    if (prettyPrint) {
      output.put(s.replace("\n", PAD[0..depth*2+1]));
    } else {
      output.put(s);
    }
  }

  void put(T)() if (isBasicType!T && !is(T:string)) {
    output.put(s.to!string);
  }

  void put(bool b) {
    output.put(b ? "true" : "false");
  }

  void newline() {
    if (prettyPrint) {
      put("\n");
    }
  }

  void comma() {
    if (prettyPrint) {
      put(", ");
    } else {
      put(",");
    }
  }

  void pointer(string p) {
    put("{\"$ref\":\"");
    put(p);
    put("\"}");
  }

  void indent() { depth++; }
  void outdent() { depth--; }

  string pointer() { return "#/" ~ pointerParts.items.map!(a=>a.to!string).join("/"); }
  @property auto data() { return output.data; }
}
