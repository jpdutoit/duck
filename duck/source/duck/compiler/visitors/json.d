module duck.compiler.visitors.json;

import duck.compiler.visitors.visit;
import duck.compiler;
import duck.util;

import std.traits: isBasicType;
import std.conv: to;
import std.range.primitives;

string generateJson(Context context) {
  auto output = JsonOutput();
  output.put(context);
  return output.output.data;
}

private size_t address(Node node) {
  return cast(size_t)cast(void*)node;
}

struct JsonOutput {
  auto output = JsonAppender();

  string[size_t] backReferences;
  string getBackReference(Node node) {
    string* name = node.address in backReferences;
    if (name is null) { return null; }
    return *name;
  }

  void put(Node node) {
    if (node is null) {
      return output.put("null");
    }

    auto reference = getBackReference(node);
    if (reference !is null) {
      return output.pointer(reference);
    }

    output.dictStart();
    backReferences[node.address] = output.pointer;
    node.accept(this);
    if (node.source)
      field("source", node.source.toLocationString);
    output.dictEnd();
  }

  void field(T)(string name, T nodes) if (is(ElementType!T: Node)) {
    output.dictField(name);
    output.arrayStart();
    foreach (node; nodes) {
      output.arrayItem();
      put(node);
    }
   output.arrayEnd();
  }

  void field(T : Node)(string name, T node) {
   output.dictField(name);
   put(node);
  }

  void field(string name, string value) { output.dictField(name, value); }
  void field(string name, bool value)   { output.dictField(name, value); }
  void field(string name, Slice value)  { output.dictField(name, value.toString()); }
  void field(string name, long value)    { output.dictField(name, value.to!string()); }
  void field(string name, double value)    { output.dictField(name, value.to!string()); }

  void visit(TypeDecl decl) {
    field("type", "declaration.builtin_type");
    field("name", decl.name.toString());
  }

  void visit(ArrayDecl decl) {
    field("type", "declaration.array");
    //field("element_type", decl.elementType);
    if (auto type = decl.declaredType.as!StaticArrayType) {
      field("length", type.size);
    }
  }

  void visit(CallableDecl decl) {
    field("type", "declaration.callable");
    field("name", decl.name.toString());
    if (decl.parameters.elements.length > 0)
      field("parameters", decl.parameters.elements);
    if (decl.isOperator)
      field("is_operator", decl.isOperator);
    if (decl.isExternal)
      field("is_external", decl.isExternal);
    if (decl.callableBody)
      field("body", decl.callableBody);


    if (decl.returnExpr) {
      if (decl.returnExpr.type.as!MetaType)
        field("return_type_declaration", (cast(RefExpr)decl.returnExpr).decl);
      else
        field("expansion", decl.returnExpr);
      }
  }

  void visit(AliasDecl decl) {
    field("type", "declaration.alias");
    field("name", decl.name.toString());
    field("value", decl.value);
  }

  void visit(ParameterDecl decl) {
    field("type", "declaration.callable.parameter");
    if (decl.name)
      field("name", decl.name.toString());
  }

  void visit(VarDecl decl) {
    import std.stdio;
    field("type", "declaration.variable");
    field("name", decl.name);
    if (decl.typeExpr)
      field("type-expression", decl.typeExpr);
    if (decl.valueExpr)
      field("value-expression", decl.valueExpr);
    if (decl.isExternal)
      field("is_external", decl.isExternal);
  }

  void visit(StructDecl decl) {
    field("type", "declaration.module");
    if (decl.isExternal)
      field("is_external", decl.isExternal);
    if (cast(ModuleDecl)decl !is null)
      field("is_module", true);
    field("context", decl.context);
    if (!decl.all.empty)
      field("members", decl.all);
  }

  void visit(Node node) {
    import std.regex;
    auto s = node.classinfo.name.replaceFirst(regex(r"^.*\."), "");
    field("type", s);
  }

  void visit(ErrorExpr expr) {
    field("type", "expression.error");
  }

  void visit(LiteralExpr expr) {
    if (expr.as!FloatValue) {
        field("type", "expression.literal.float");
        field("value", expr.as!FloatValue.value);
    } else if (expr.type.as!IntegerType) {
        field("type", "expression.literal.int");
        field("value", expr.as!IntegerValue.value);
    } else if (expr.type.as!StringType) {
        field("type", "expression.literal.string");
        field("value", expr.as!StringValue.value);
    } else if (expr.type.as!BoolType) {
        field("type", "expression.literal.bool");
        field("value", expr.as!BoolValue.value);
    } else {
      field("type", "expression.literal.error");
    }
  }

  void visit(FloatValue expr) {
    field("type", "expression.literal.float");
    field("value", expr.value);
  }

  void visit(IntegerValue expr) {
    field("type", "expression.literal.int");
    field("value", expr.value);
  }

  void visit(StringValue expr) {
    field("type", "expression.literal.string");
    field("value", expr.value);
  }

  void visit(BoolValue expr) {
    field("type", "expression.literal.bool");
    field("value", expr.value ? "true" : "false");
  }

  void visit(RefExpr expr) {
   field("type", "expression.reference");
   if (expr.context)
     field("context", expr.context);
   field("declaration", expr.decl);
  }

  void visit(CallExpr expr) {
   field("type", "expression.call");
   field("target", expr.callable);
   field("arguments", expr.arguments.elements);
  }

  void visit(AssignExpr expr) {
   field("type", "expression.assign");
   field("operator", expr.operator.toString());
   field("arguments", expr.arguments);
  }

  void visit(BinaryExpr expr) {
   field("type", "expression.binary");
   field("operator", expr.operator.toString());
   field("arguments", expr.arguments);
  }

  void visit(CastExpr expr) {
    field("type", "expression.cast");
    field("argument", expr.expr);
  }

  void visit(ExprStmt stmt) {
   field("type", "statement.expression");
   field("expression", stmt.expr);
  }

  void visit(DeclStmt stmt) {
   field("type", "statement.declaration");
   //field("name", stmt.identifier.toString());
   field("declaration", stmt.decl);
  }

  void visit(BlockStmt block) {
   field("type", "statement.block");
   field("is_scope", block.as!ScopeStmt !is null);
   field("statements", block.array);
  }

  void visit(ReturnStmt stmt) {
    field("type", "statement.return");
    field("argument", stmt.value);
  }

  void visit(ImportDecl stmt) {
    field("type", "declaration.import");
    field("name", stmt.identifier.length > 0 ? stmt.identifier[1..$-1] : "");
    if (stmt.targetContext) {
      field("library", stmt.targetContext.parsed);
    }
  }

  void visit(Library library) {
   field("type", "library");
   output.dictField("declarations");
   output.dictStart();

   bool[string] seen;
   foreach (v; library.globals.all) {
     string key = v.name.toString();
     if (key in seen) continue;
     seen[key] = true;

     auto decls = library.globals.symbols[key];
     field(key, decls);
   }
   output.dictEnd();
   field("statements", library.stmts.array);
  }

  void put(Context context) {
    import std.algorithm, std.range;
    output.dictStart();
    field("builtins", []);
    field("libraries", context.dependencies.retro.map!((context) => context.parsed).array ~ context.parsed);
    field("main", context.parsed);
    output.dictEnd();
  }
}
