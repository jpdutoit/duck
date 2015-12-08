module duck.compiler.visitors.codegen;

import std.stdio;

//debug = CodeGen;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.transforms;
import duck.compiler;
import duck.compiler.context;
import duck.compiler.visitors;

import duck.compiler.dbg;

//  This code generator is a bit of hack at the moment

string generateCode(Node node, Context context) {
  CodeGen cg = CodeGen(context);
  node.accept(cg);
  return cg.output.data;
}


struct LValueToString {
  string prefix;
  string visit(RefExpr re) {
    return re.identifier.value;
  }
  string visit(MemberExpr me) {
    return me.expr.accept(this) ~ "." ~ me.identifier.value;
  }
  string visit(Node node) {
    throw __ICE("Internal compiler error (LValueToString)");
  }
}

auto lvalueToString(Node node) {
  return node.accept(LValueToString());
}

struct FindTarget {
  string visit(Node node) {
    return null;
  }
  string visit(MemberExpr expr) {
    return expr.expr.accept(LValueToString());
  }
};
auto findTarget(Node node) {
  return node.accept(FindTarget());
}

struct FindOwnerDecl {
  StructDecl visit(Node node) {
    return null;
  }
  StructDecl visit(MemberExpr expr) {
    if (auto ge = cast(GeneratorType)expr.expr.exprType) {
      return ge.decl;
    }
    return expr.expr.accept(this);
    /*if (expr.expr.exprType.kind == GeneratorType.Kind)) return expr.expr;
    if (cast(MemberExpr)expr.expr) {
      return accept(expr.expr);
    }
    return expr.expr.
    return accept(expr.expr);*/
  }
};

auto findOwnerDecl(Node node) {
  //stderr.writeln((cast(Expr)node).print);
  return node.accept(FindOwnerDecl());
}


struct FindGenerators {
  string[] generators;

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

struct CodeAppender {
  import std.array;
  int depth = 0;
  Appender!string output;

  enum string PAD = "\n\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";
  void put(string s) {
    import std.string;
    output.put(s.replace("\n", PAD[0..depth+1]));
  }

  void indent() {
    depth++;
  }

  void outdent() {
    depth--;
  }

  auto data() {
    return output.data;
  }
}

struct CodeGen {
  debug(CodeGen) mixin TreeLogger;

  CodeAppender output;

  string[] generators;

  Context context;

  this(Context context) {
    this.context = context;
  }

  void emit(string s) {
    output.put(s);
  }

  void indent() { output.indent(); }
  void outdent() { output.outdent(); }

  void accept(Node n) {
    debug(CodeGen) logIndent();
    n.accept(this);
    debug(CodeGen) logOutdent();
  }

  void visit(MemberExpr expr) {
    debug(CodeGen) log("MemberExpr");
    //string owner = accept(expr.expr);


//      writefln("%s", expr.expr.exprType);

      //emit("(");
      accept(expr.expr);
      emit(".");
      emit(expr.identifier.value);
      //emit(")");
      //writefln("FF");
      //return "(" ~ expr.expr.accept(this) ~ "._" ~ expr.identifier.value ~ ")";
  }

  void visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
    debug(CodeGen) log("Ident/LiteralExpr");
    emit(expr.token.value);
  }
  void visit(ArrayLiteralExpr expr) {
    debug(CodeGen) log("ArrayLiteralExpr");
    emit("[");
    foreach (i, expr1 ; expr.exprs) {
      if (i != 0) emit(",");
      expr1.accept(this);
    }
    emit("]");
  }
  void visit(BinaryExpr expr) {
    debug(CodeGen) log("BinaryExpr");
    emit("(");
    accept(expr.left);
    emit(expr.operator.value);
    accept(expr.right);
    emit(")");
  }

  void visit(PipeExpr expr) {
    debug(CodeGen) log("PipeExpr", expr);

    string target = expr.right.findTarget();
    generators = findGenerators(expr.left);

    if (generators.length == 0) {
      debug(CodeGen) log("=> Rewrite as:");
      accept(new AssignExpr(context.token(Tok!"=", "="), expr.right, expr.left));
      /*accept(expr.right);
      emit(" = ");
      accept(expr.left);*/
      return;
    }

    StructDecl owner = findOwnerDecl(expr.right);
    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

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
      accept(expr.right);
      emit(" = ");
      accept(expr.left);
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
      accept(expr.right);
      emit(" = ");
      accept(expr.left);
      emit(";})");
    }
  }
  void visit(AssignExpr expr) {
    debug(CodeGen) log("AssignExpr", expr);

    StructDecl owner = findOwnerDecl(expr.left);
    string target = expr.left.findTarget();
    generators = findGenerators(expr.right);


    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

    if (owner && !owner.external) {
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

    debug(CodeGen) log("=> LHS:");
    accept(expr.left);
    emit(expr.operator.value);
    debug(CodeGen) log("=> RHS:");
    accept(expr.right);
    //return "assign!\""~expr.operator.value~"\"(" ~ expr.left.accept(this) ~ "," ~  expr.right.accept(this) ~ ")";
  }
  void visit(UnaryExpr expr) {
    debug(CodeGen) log("UnaryExpr");
    emit("(");
    emit(expr.operator.value);
    accept(expr.operand);
    emit(")");
  }
  void visit(CallExpr expr) {
    debug(CodeGen) log("CallExpr");
    accept(expr.expr);
    emit("(");
    //if (expr.arguments.length == 1)
    //  s = "call!" ~ s;
    foreach (i, arg ; expr.arguments) {
      if (i != 0) emit(",");
      accept(arg);
    }
    emit(")");
  }
  void visit(VarDeclStmt stmt) {
    debug(CodeGen) log("VarDeclStmt");
    //import duck.compiler.visitors;
    //writefln("VarDeclStmt %s %s", stmt.decl, stmt.decl.accept(ExprPrint()));
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
        accept(stmt.expr);
        emit(";\n");
        return;
      case NumberType.Kind:
        emit("float ");
        emit(stmt.identifier.value);
        emit(" = ");
        accept(stmt.expr);
        emit(";\n");
        return;
        //return (cast(GeneratorType)stmt.decl.declType).name ~ " " ~ stmt.identifier.value ~ " = " ~ stmt.expr.accept(this) ~ ";\n";
      default: throw __ICE("Code generation not implemnted for " ~ stmt.decl.declType.mangled);
    }
  }
  void visit(TypeDeclStmt stmt) {
    accept(stmt.decl);
  }

  void visit(ExprStmt stmt) {

    debug(CodeGen) log("ExprStmt");
    accept(stmt.expr);
    emit(";\n");
  }

  void line(Node node) {
    auto slice = node.accept(LineNumber());
    if (cast(FileBuffer)slice.buffer) {
      import std.conv : to;
      emit("#line ");
      emit(slice.lineNumber.to!string);
      emit(" \"");
      emit(slice.buffer.name);
      emit("\" ");
      emit("\n");
    }
  }

  void visit(Stmts expr) {
    debug(CodeGen) log("Stmts");
    emit("\n");
    import duck.compiler.visitors;
    foreach (i, stmt; expr.stmts) {
      if (!cast(Stmts)stmt) line(stmt);
      accept(stmt);
    }
  }
  void visit(TypeExpr expr) {
    accept(expr.expr);
  }
  void visit(RefExpr expr) {
    debug(CodeGen) log("RefExpr");
    emit(expr.identifier.value);
  }
  void visit(ScopeStmt expr) {
    debug(CodeGen) log("ScopeStmt");
    indent();
    emit("{\n");
    accept(expr.stmts);
    outdent();
    emit("\n}\n");
  }
  void visit(FieldDecl fieldDecl) {
    line(fieldDecl.typeExpr);

    emit("__ConnDg ");
    emit(fieldDecl.name.value);
    emit("__dg; ");

    emit("  ");
    accept(fieldDecl.typeExpr);
    emit(" ");
    emit(fieldDecl.name.value);
    if (fieldDecl.valueExpr) {
      emit(" = ");
      accept(fieldDecl.valueExpr);
    }
    emit(";\n");
  }

  void visit(MethodDecl methodDecl) {
    emit("void ");
    emit(methodDecl.name.value);
    emit("(");
    emit(") ");
    //emit("{");
    accept(methodDecl.methodBody);
    //emit("  }");
  }

  void visit(MacroDecl aliasDecl) {
  }

  void visit(StructDecl structDecl) {
    debug(CodeGen) log("Struct", structDecl.name.value);
    if (!structDecl.external) {
        emit("struct ");
        emit(structDecl.name.value);
        emit(" {");
        indent();
        emit("\n");
        foreach(field ; structDecl.symbolsInDefinitionOrder) {
          accept(field);
        }
        emit("ulong __sampleIndex = ulong.max;\n");

        emit("\n");
        emit("void _tick() {");
        indent();
        emit("\n");
        emit(
          "if (__sampleIndex == __idx) return;\n"
          "__sampleIndex = __idx;\n\n"
        );

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
          emit("tick();");
        }
        outdent();
        emit("\n}");
        outdent();
        emit("\n}\n\n");
    }
  }

  void visit(Program mod) {
    debug(CodeGen) log("Program");
    indent();
    foreach (i, decl; mod.imported.symbolsInDefinitionOrder) {
      accept(decl);
    }
    /*foreach (i, decl; mod.decls) {
      accept(decl);
    }*/
    foreach (i, node; mod.nodes) {
      accept(node);
    }
    outdent();
    //writefln("%s", output.data);
    //return output.data;
  }
};
