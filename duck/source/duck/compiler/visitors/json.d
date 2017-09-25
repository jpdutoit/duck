module duck.compiler.visitors.json;

import duck.compiler.visitors.visit;
import duck.compiler.buffer, duck.compiler.ast, duck.compiler.lexer;
import duck.compiler.context;
import duck.util;

import std.traits: isBasicType;
import std.conv: to;

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
    if (auto expr = cast(Expr)node) {
      if (expr.source)
       field("source", expr.source.toLocationString);
     }
    output.dictEnd();
  }

  void field(T : Node)(string name, T[] nodes) {
    output.dictField(name);
    output.arrayStart();
    foreach (i, node; nodes) {
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

  void visit(TypeDecl decl) {
    field("type", "declaration.builtin_type");
    field("name", decl.name.toString());
  }

  void visit(ArrayDecl decl) {
    field("type", "declaration.array");
    field("element_declaration", decl.elementDecl);
    //TODO: Add static array size
  }

  void visit(OverloadSet decl) {
    field("type", "declaration.overload_set");
    field("overloads", decl.decls);
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
    if (decl.isMethod)
      field("is_method", decl.isMethod);
    if (decl.isMacro)
      field("is_macro", decl.isMacro);
    if (decl.callableBody)
      field("body", decl.callableBody);
    if (decl.isMacro && decl.returnExpr)
      field("expansion", decl.returnExpr);
    if (!decl.isMacro && cast(RefExpr)decl.returnExpr)
      field("return_type_declaration", (cast(RefExpr)decl.returnExpr).decl);
  }

  void visit(ParameterDecl decl) {
    field("type", "declaration.callable.parameter");
    if (decl.name)
      field("name", decl.name.toString());
    field("type-declaration", decl.typeExpr.decl);
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

  void visit(FieldDecl decl) {
    field("type", "declaration.struct.field");
    field("name", decl.name.toString());
    if (decl.valueExpr)
      field("value_expression", decl.valueExpr);
  }

  void visit(StructDecl decl) {
    field("type", "declaration.module");
    if (decl.isExternal)
      field("is_external", decl.isExternal);
    if (cast(ModuleDecl)decl !is null)
      field("is_module", true);
    field("context", decl.context);
    if (decl.all.length > 0)
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
    field("type", "expression.literal");
    field("value", expr.value.toString());
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

  void visit(ImportStmt stmt) {
    field("type", "statement.import");
    field("name", stmt.identifier);
    field("library", stmt.targetContext.library);
  }

  void visit(Library library) {
   field("type", "library");
   output.dictField("declarations");
   output.dictStart();

   bool[string] seen;
   foreach (v; library.globals.table.all) {
     string key = v.name.toString();
     if (key in seen) continue;
     seen[key] = true;

     auto value = library.globals.table.symbols[key];
     auto os = cast(OverloadSet)value;
     if (os && os.decls.length == 1) {
       field(key, os.decls[0]);
     } else {
      field(key, value);
    }
   }
   output.dictEnd();
   field("statements", library.stmts.array);
  }

  void put(Context context) {
    import std.algorithm, std.range;
    output.dictStart();
    field("builtins", []);
    field("libraries", context.dependencies.retro.map!((context) => context.library).array ~ context.library);
    field("main", context.library);
    output.dictEnd();
  }
}
