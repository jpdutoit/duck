module duck.compilers.visitors.codegen;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
debug import duck.compilers.visitors.expr_to_string;
import duck.compiler;
//debug = CodeGen;

//  This code generator is a bit of hack at the moment

struct CodeGen {
  alias VisitResultType = String;
  import std.array;
  Appender!String output;

  bool refer = false;
  bool write = true;
  String[] generators;

  void emit(String s) {
    if (write) {
      output.put(s);
    }
  }

  String chainToString(Expr expr) {
    if (auto re = cast(RefExpr)expr) {
      return re.identifier.value;
    }
    else if (auto me = cast(MemberExpr)expr) {
      return chainToString(me.expr) ~ "._" ~ me.identifier.value;
    }
    else throw __ICE("Internal compiler error (chainToString)");
  }

  String visit(MemberExpr expr) {
    debug(CodeGen) writefln("MemberExpr");
    //String owner = expr.expr.accept(this);
    if (refer) {
      debug(CodeGen) writefln("DDDD %s %s %s %s", expr.expr, expr.expr.accept(ExprToString()), expr.expr.exprType.mangled, expr.identifier.value);

      if (expr.expr.exprType.kind == GeneratorType.Kind) {
        //generators ~= (cast(RefExpr)expr.expr).identifier.value;
        generators ~= chainToString(expr.expr);
        //generator ~= )
      }
      return chainToString(expr.expr);
      //return (cast(RefExpr)expr.expr).identifier;
    }
      //return "refer(&" ~ owner ~ ", &" ~ owner ~ "._" ~ expr.identifier.value ~ ")";
    else {


//      writefln("%s", expr.expr.exprType);

      //emit("(");
      expr.expr.accept(this);
      emit("._");
      emit(expr.identifier.value);
      //emit(")");
      //writefln("FF");
      return null;
      //return "(" ~ expr.expr.accept(this) ~ "._" ~ expr.identifier.value ~ ")";
    }
  }

  String visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    debug(CodeGen) writefln("Ident/LiteralExpr");
    emit(expr.token.value);
    return null;
  }
  String visit(ArrayLiteralExpr expr) {
    debug(CodeGen) writefln("ArrayLiteralExpr");
    emit("[");
    foreach (i, expr1 ; expr.exprs) {
      if (i != 0) emit(",");
      expr1.accept(this);
    }
    emit("]");
    return null;
  }
  String visit(BinaryExpr expr) {
    debug(CodeGen) writefln("BinaryExpr");
    emit("(");
    expr.left.accept(this);
    emit(expr.operator.value);
    expr.right.accept(this);
    emit(")");
    return null;
  }
  String visit(PipeExpr expr) {
    debug(CodeGen) writefln("PipeExpr");
    //auto a = delegate() { 1 + 2; };
    //a();

    // return "(delegate() { " ~ expr.right.accept(this) ~ " = " ~ expr.left.accept(this) ~ "; })()";
    refer = true;
    write = false;
    String target = expr.right.accept(this);
    generators = [];
    expr.left.accept(this);
    write = true;
    refer = false;
    if (generators.length == 0) {
      expr.right.accept(this);
      emit(" = ");
      expr.left.accept(this);
      return null;
    }



    emit(target);
    emit(".__add(() { ");

    foreach(gen; generators) {
      //if (auto declExpr = cast(DeclExpr)gen) {
      emit(gen);
      emit("._tick(); ");
      //}
    }
    emit(" ");
    expr.right.accept(this);
    emit(" = ");
    expr.left.accept(this);
    emit(";})");

    //auto s =  ~ ticks ~ " " ~ target2 ~ " = " ~ e ~";})";// writefln(\"%s\", " ~ e ~ ");})";
    return null;
    //return "pipe(" ~ expr.left.accept(this) ~ "," ~ expr.right.accept(this) ~ ")";
  }
  String visit(AssignExpr expr) {
    refer = true;
    write = false;
    String target = expr.left.accept(this);
    generators = [];
    expr.right.accept(this);
    write = true;
    refer = false;

    foreach(gen; generators) {
      //if (auto declExpr = cast(DeclExpr)gen) {
      if (gen == "this") continue;
      emit(gen);
      emit("._tick(); ");
      //}
    }
    debug(CodeGen) writefln("AssignExpr");
    expr.left.accept(this);
    emit(expr.operator.value);
    expr.right.accept(this);
    return null;
    //return "assign!\""~expr.operator.value~"\"(" ~ expr.left.accept(this) ~ "," ~  expr.right.accept(this) ~ ")";
  }
  String visit(UnaryExpr expr) {
    debug(CodeGen) writefln("UnaryExpr");
    emit("(");
    emit(expr.operator.value);
    expr.operand.accept(this);
    emit(")");
    return null;
  }
  String visit(CallExpr expr) {
    debug(CodeGen) writefln("CallExpr");
    expr.expr.accept(this);
    emit("(");
    //if (expr.arguments.length == 1)
    //  s = "call!" ~ s;
    foreach (i, arg ; expr.arguments) {
      if (i != 0) emit(",");
      arg.accept(this);
    }
    emit(")");
    return null;
  }
  String visit(DeclStmt stmt) {
    debug(CodeGen) writefln("DeclStmt");
    //import duck.compiler.visitors;
    //writefln("DeclStmt %s %s", stmt.decl, stmt.decl.accept(ExprPrint()));
    switch (stmt.decl.declType.kind) {
      case StructType.Kind:
        emit((cast(StructType)stmt.decl.declType).name);
        emit(" ");
        emit(stmt.identifier.value);
        emit(";\n");
        return null;
      case GeneratorType.Kind:
        emit((cast(GeneratorType)stmt.decl.declType).name);
        emit(" ");
        emit(stmt.identifier.value);
        emit(" = ");
        stmt.expr.accept(this);;
        emit(";\n");
        return null;
      case NumberType.Kind:
        emit("float ");
        emit(stmt.identifier.value);
        emit(" = ");
        stmt.expr.accept(this);
        emit(";\n");
        return null;
        //return (cast(GeneratorType)stmt.decl.declType).name ~ " " ~ stmt.identifier.value ~ " = " ~ stmt.expr.accept(this) ~ ";\n";
      default: throw __ICE("Code generation not implemnted for " ~ stmt.decl.declType.mangled);
    }
  }
  String visit(ExprStmt stmt) {
    debug(CodeGen) writefln("ExprStmt");
    stmt.expr.accept(this);
    emit(";\n");
    return null;
  }
  String visit(Stmts expr) {
    debug(CodeGen) writefln("Stmts");
    import duck.compiler.visitors;
    import std.conv : to;
    foreach (i, stmt; expr.stmts) {
      auto span = stmt.accept(LineNumber());
      if (span.a.line > 0) {
        emit("#line ");
        emit(span.a.line.to!String);
        emit(" \"\" ");
        emit("\n");
      }
      stmt.accept(this);
    }
    return null;
  }
  String visit(TypeExpr expr) {
    expr.expr.accept(this);
    return null;
  }
  String visit(RefExpr expr) {
    debug(CodeGen) writefln("RefExpr");
    emit(expr.identifier.value);
    return null;
    //return expr.identifier.value;
    //import duck.compiler.visitors;
    //writefln("%s %s", expr.decl, expr.decl.accept(ExprPrint()));
    //return expr.decl.accept(this);
  }
  String visit(ScopeStmt expr) {
    debug(CodeGen) writefln("ScopeStmt");
    emit("{");
    expr.stmts.accept(this);
    emit("}\n");
    return null;
  }
  String visit(FieldDecl fieldDecl) {
    emit("  ");
    fieldDecl.typeExpr.accept(this);
    emit(" _");
    emit(fieldDecl.name.value);
    if (fieldDecl.valueExpr) {
      emit(" = ");
      fieldDecl.valueExpr.accept(this);
    }
    emit(";\n");
    return null;
  }

  String visit(MethodDecl methodDecl) {
    emit("  void");
    emit(" ");
    emit(methodDecl.name.value);
    emit("(");
    emit(") ");
    //emit("{");
    methodDecl.methodBody.accept(this);
    //emit("  }");
    return null;
  }

  String visit(MacroDecl aliasDecl) {
    return null;
  }

  String visit(StructDecl structDecl) {
    debug(CodeGen) writefln("Struct %s", structDecl.name.value);
    if (!structDecl.external) {
        emit("struct ");
        emit(structDecl.name.value);
        emit(" {\n");
        foreach(field ; structDecl.symbolsInDefinitionOrder) {
          field.accept(this);
        }
        emit("ulong __sampleIndex = ulong.max;\n");
        emit("__ConnDg[] __connections;\n");

        emit("\n");
        emit("void _tick() {\n");
        emit(q{
          if (__sampleIndex == __idx)
            return;

          __sampleIndex = __idx;
          // Process connections
          for (int c = 0; c < __connections.length; ++c) {
            __connections[c]();
          }
        });
        if (structDecl.defines("tick")) {
          emit("tick();\n");
        }
        emit("}\n");
        emit(q{
          void __add(scope void delegate() @system dg) {
            __connections ~= dg;
          }
        });
        emit("}\n");
    }
    return null;
  }

  String visit(Program mod) {
    debug(CodeGen) writefln("Program");
    foreach (i, decl; mod.imported.symbolsInDefinitionOrder) {
      decl.accept(this);
    }
    foreach (i, decl; mod.decls) {
      decl.accept(this);
    }
    foreach (i, node; mod.nodes) {
      node.accept(this);
    }
    debug(CodeGen) writefln("Program2");
    //writefln("%s", output.data);
    return output.data;
  }
};
