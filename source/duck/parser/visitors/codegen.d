module duck.compilers.visitors.codegen;

import std.stdio;

//debug = CodeGen;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
import duck.compiler;
import duck.compiler.context;
import duck.compiler.visitors;

import duck.compiler.dbg;

//  This code generator is a bit of hack at the moment

String generateCode(Node node, Context context) {
  CodeGen cg = CodeGen(context);
  node.accept(cg);
  return cg.output.data;
}


struct LValueToString {
  String prefix;
  String visit(RefExpr re) {
    return re.identifier.value;
  }
  String visit(MemberExpr me) {
    return me.expr.accept(this) ~ "." ~ me.identifier.value;
  }
  String visit(Node node) {
    throw __ICE("Internal compiler error (LValueToString)");
  }
}

auto lvalueToString(Node node) {
  return node.accept(LValueToString());
}

struct FindTarget {
  String visit(Node node) {
    return null;
  }
  String visit(MemberExpr expr) {
    return expr.expr.accept(LValueToString());
  }
};
auto findTarget(Node node) {
  return node.accept(FindTarget());
}

struct FindOwnerDecl {
  int depth = 0;
  StructDecl visit(Node node) {
    return null;
  }
  StructDecl visit(MemberExpr expr) {

    if (expr.expr.exprType.kind != GeneratorType.Kind)
      return expr.expr.accept(this);
    return cast(StructDecl)expr.expr.exprType.decl;
    /*if (expr.expr.exprType.kind == GeneratorType.Kind)) return expr.expr;
    if (cast(MemberExpr)expr.expr) {
      return expr.expr.accept(this);
    }
    return expr.expr.
    return expr.expr.accept(this);*/
  }
};

auto findOwnerDecl(Node node) {
  //stderr.writeln((cast(Expr)node).print);
  return node.accept(FindOwnerDecl());
}


struct FindGenerators {
  String[] generators;

  void accept(Node node) {
    node.accept(this);
  }
  void visit(MemberExpr expr) {
    if (expr.expr.exprType.kind == GeneratorType.Kind) {
      generators ~= expr.findTarget();
    }
  }
  void visit(T)(T node) {
    recurse(node);
  }
  mixin DepthFirstRecurse;
};

auto findGenerators(Node node) {
  FindGenerators fg;
  node.accept(fg);
  return fg.generators;
}

struct CodeGen {

  import std.array;
  Appender!String output;

  String[] generators;

  Context context;

  this(Context context) {
    this.context = context;
  }

  void emit(String s) {
    output.put(s);
  }

  void visit(MemberExpr expr) {
    debug(CodeGen) writefln("MemberExpr");
    //String owner = expr.expr.accept(this);


//      writefln("%s", expr.expr.exprType);

      //emit("(");
      expr.expr.accept(this);
      emit(".");
      emit(expr.identifier.value);
      //emit(")");
      //writefln("FF");
      //return "(" ~ expr.expr.accept(this) ~ "._" ~ expr.identifier.value ~ ")";
  }

  void visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    debug(CodeGen) writefln("Ident/LiteralExpr");
    emit(expr.token.value);
  }
  void visit(ArrayLiteralExpr expr) {
    debug(CodeGen) writefln("ArrayLiteralExpr");
    emit("[");
    foreach (i, expr1 ; expr.exprs) {
      if (i != 0) emit(",");
      expr1.accept(this);
    }
    emit("]");
  }
  void visit(BinaryExpr expr) {
    debug(CodeGen) writefln("BinaryExpr");
    emit("(");
    expr.left.accept(this);
    emit(expr.operator.value);
    expr.right.accept(this);
    emit(")");
  }

  void visit(PipeExpr expr) {
    debug(CodeGen) writefln("PipeExpr");

    StructDecl owner = findOwnerDecl(expr.right);
    String target = expr.right.findTarget();
    generators = findGenerators(expr.left);

    if (generators.length == 0) {
      new AssignExpr(context.token(Tok!"=", "="), expr.right, expr.left).accept(this);
      /*expr.right.accept(this);
      emit(" = ");
      expr.left.accept(this);*/
      return;
    }

    if (!owner.external) {
      emit(expr.right.lvalueToString());
      emit("__dg = ");
      emit("() { ");

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
      emit(";}");
    }
    else {
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
    }
  }
  void visit(AssignExpr expr) {
    StructDecl owner = findOwnerDecl(expr.left);
    String target = expr.left.findTarget();
    generators = findGenerators(expr.right);

    if (owner) {
      emit(expr.left.lvalueToString());
      emit("__dg = ");
      emit("null;\n");
    }
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
    //return "assign!\""~expr.operator.value~"\"(" ~ expr.left.accept(this) ~ "," ~  expr.right.accept(this) ~ ")";
  }
  void visit(UnaryExpr expr) {
    debug(CodeGen) writefln("UnaryExpr");
    emit("(");
    emit(expr.operator.value);
    expr.operand.accept(this);
    emit(")");
  }
  void visit(CallExpr expr) {
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
  }
  void visit(DeclStmt stmt) {
    debug(CodeGen) writefln("DeclStmt");
    //import duck.compiler.visitors;
    //writefln("DeclStmt %s %s", stmt.decl, stmt.decl.accept(ExprPrint()));
    switch (stmt.decl.declType.kind) {
      case StructType.Kind:
        emit((cast(StructType)stmt.decl.declType).name);
        emit(" ");
        emit(stmt.identifier.value);
        emit(";\n");
        return;
      case GeneratorType.Kind:
        emit((cast(GeneratorType)stmt.decl.declType).name);
        emit(" ");
        emit(stmt.identifier.value);
        emit(" = ");
        stmt.expr.accept(this);;
        emit(";\n");
        return;
      case NumberType.Kind:
        emit("float ");
        emit(stmt.identifier.value);
        emit(" = ");
        stmt.expr.accept(this);
        emit(";\n");
        return;
        //return (cast(GeneratorType)stmt.decl.declType).name ~ " " ~ stmt.identifier.value ~ " = " ~ stmt.expr.accept(this) ~ ";\n";
      default: throw __ICE("Code generation not implemnted for " ~ stmt.decl.declType.mangled);
    }
  }
  void visit(ExprStmt stmt) {
    debug(CodeGen) writefln("ExprStmt");
    stmt.expr.accept(this);
    emit(";\n");
  }
  void visit(Stmts expr) {
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
  }
  void visit(TypeExpr expr) {
    expr.expr.accept(this);
  }
  void visit(RefExpr expr) {
    debug(CodeGen) writefln("RefExpr");
    emit(expr.identifier.value);
  }
  void visit(ScopeStmt expr) {
    debug(CodeGen) writefln("ScopeStmt");
    emit("{");
    expr.stmts.accept(this);
    emit("}\n");
  }
  void visit(FieldDecl fieldDecl) {
    emit("  ");
    fieldDecl.typeExpr.accept(this);
    emit(" ");
    emit(fieldDecl.name.value);
    if (fieldDecl.valueExpr) {
      emit(" = ");
      fieldDecl.valueExpr.accept(this);
    }
    emit(";\n");
  }

  void visit(MethodDecl methodDecl) {
    emit("  void");
    emit(" ");
    emit(methodDecl.name.value);
    emit("(");
    emit(") ");
    //emit("{");
    methodDecl.methodBody.accept(this);
    //emit("  }");
  }

  void visit(MacroDecl aliasDecl) {
  }

  void visit(StructDecl structDecl) {
    debug(CodeGen) writefln("Struct %s", structDecl.name.value);
    if (!structDecl.external) {
        emit("struct ");
        emit(structDecl.name.value);
        emit(" {\n");
        foreach(field ; structDecl.symbolsInDefinitionOrder) {
          field.accept(this);
          if (auto fd = cast(FieldDecl)field) {
            emit("__ConnDg ");
            emit(fd.name.value);
            emit("__dg;\n");
          }
        }
        emit("ulong __sampleIndex = ulong.max;\n");

        emit("\n");
        emit("void _tick() {\n");
        emit(q{
          if (__sampleIndex == __idx) return;
          __sampleIndex = __idx;
        });

        foreach(field ; structDecl.symbolsInDefinitionOrder) {
          if (auto fd = cast(FieldDecl)field) {
            emit("if (");
            emit(fd.name.value);
            emit("__dg) ");
            emit(fd.name.value);
            emit("__dg();\n");
          }
        }
        if (structDecl.defines("tick")) {
          emit("tick();\n");
        }
        emit("}\n");
        emit("}\n");
    }
  }

  void visit(Program mod) {
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
    //return output.data;
  }
};
