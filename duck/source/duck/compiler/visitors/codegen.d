module duck.compiler.visitors.codegen;

import std.stdio;

//debug = CodeGen;

import duck.compiler.ast;
import duck.compiler.lexer.tokens;
import duck.compiler.types;
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

string lvalueToString(Expr expr){
  return expr.visit!(
    (RefExpr re) => re.identifier.value,
    (IdentifierExpr ie) => ie.token.value,
    (MemberExpr me) => lvalueToString(me.left) ~ "." ~ lvalueToString(me.right));
}

string findTarget(Expr expr) {
  return expr.visit!(
    (Expr expr) => cast(string)null,
    (MemberExpr expr) => lvalueToString(expr.left));
}

StructDecl findOwnerDecl(Expr expr) {
  return expr.visit!(
    (Expr expr) => cast(StructDecl)null,
    delegate StructDecl(MemberExpr expr) {
      if (auto ge = cast(ModuleType)expr.left.exprType) {
        return ge.decl;
      }
      return expr.left.findOwnerDecl();
    });
}

auto findModules(Expr expr) {
  string[] modules;
  expr.traverse((MemberExpr memberExpr) {
    if (memberExpr.left.exprType.kind == ModuleType.Kind) {
      modules ~= memberExpr.findTarget();
      //return false;
    }
    return true;
  });
  return modules;
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
  CodeAppender output;

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
      accept(expr.left);
      emit(".");
      accept(expr.right);
      //emit(expr.right.value);
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
    auto modules = findModules(expr.left);

    if (modules.length == 0) {
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

      foreach(mod; modules) {
        //if (auto declExpr = cast(DeclExpr)gen) {
        emit(mod);
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

      foreach(mod; modules) {
        //if (auto declExpr = cast(DeclExpr)gen) {
        emit(mod);
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
    auto modules = findModules(expr.right);


    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

    if (owner && !owner.external) {
      emit(expr.left.lvalueToString());
      emit("__dg = ");
      emit("null;\n");
    }
    foreach(mod; modules) {
      //if (auto declExpr = cast(DeclExpr)gen) {
      if (mod == "this") continue;
      emit(mod);
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

  void visit(TupleExpr expr) {
    foreach (i, arg ; expr.elements) {
      if (i != 0) emit(",");
      accept(arg);
    }
  }

  void visit(CallExpr expr) {
    debug(CodeGen) log("CallExpr");
    accept(expr.expr);
    emit("(");
    accept(expr.arguments);
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
      case ModuleType.Kind:
        emit((cast(ModuleType)stmt.decl.declType).name);
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
        //return (cast(ModuleType)stmt.decl.declType).name ~ " " ~ stmt.identifier.value ~ " = " ~ stmt.expr.accept(this) ~ ";\n";
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

    foreach (i, Stmt stmt; expr.stmts) {
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

  void visit(Library library) {
    debug(CodeGen) log("Library");
    indent();
    foreach (i, node; library.nodes) {
      accept(node);
    }
    outdent();
  }
};
