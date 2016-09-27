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

string typeString(Type type) {
  import std.conv: to;
  return type.visit!(
    (ModuleType m) => m.name,
    (StructType t) => t.name,
    (StringType t) => "string",
    (NumberType t) => "float",
    (ArrayType t) => typeString(t.elementType) ~ "[]",
    (StaticArrayType t) => typeString(t.elementType) ~ "[" ~ t.size.to!string ~ "]"
  );
}

string lvalueToString(Expr expr){
  return expr.visit!(
    (RefExpr re) => re.identifier.value,
    (IdentifierExpr ie) => ie.identifier,
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
    accept(expr.left);
    emit(".");
    accept(expr.right);
  }

  void visit(IdentifierExpr expr) {
    debug(CodeGen) log("IdentifierExpr");
    emit(expr.identifier);
  }

  void visit(LiteralExpr expr) {
    debug(CodeGen) log("LiteralExpr");
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

  void instrument(Expr value, Expr target) {
    auto slice = value.accept(LineNumber());
    emit("\n");
    emit("instrument(\"");
    emit(slice.toLocationString());
    emit(": ");
    emit(slice.toString());
    emit("\"");
    emit(", cast(void*)&");
    accept(target);
    emit(", ");
    accept(value);
    emit(");");
  }

  void visit(PipeExpr expr) {
    debug(CodeGen) log("PipeExpr", expr);

    string target = expr.right.findTarget();
    auto modules = findModules(expr.left);

    if (modules.length == 0) {
      debug(CodeGen) log("=> Rewrite as:");
      accept(new AssignExpr(context.token(Tok!"=", "="), expr.right, expr.left));
      return;
    }

    StructDecl owner = findOwnerDecl(expr.right);
    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

    if ((cast(ModuleDecl)owner is null)) {
      accept(expr.right);
      emit(" = ");
      accept(expr.left);
      emit(";");
      return;
    }

    if (!owner.external) {
      emit(expr.right.lvalueToString());
      emit("__dg = ");
      emit("() {");
      indent();

      foreach(mod; modules) {
        //if (auto declExpr = cast(DeclExpr)gen) {
        emit("\n");
        emit(mod);
        emit("._tick(); ");
        //}
      }
      emit("\n");
      accept(expr.right);
      emit(" = ");
      accept(expr.left);
      emit(";");
      if (context.instrument) {
        instrument(expr.left, expr.right);
      }
      outdent();
      emit("\n}");
    }
    else {
      emit(target);
      emit(".__add((){ ");
      indent();

      foreach(mod; modules) {
        //if (auto declExpr = cast(DeclExpr)gen) {
        emit("\n");
        emit(mod);
        emit("._tick(); ");
        //}
      }
      emit("\n");
      accept(expr.right);
      emit(" = ");
      accept(expr.left);
      emit(";");
      if (context.instrument) {
        instrument(expr.left, expr.right);
      }
      outdent();
      emit("\n;})");

    }
  }
  void visit(AssignExpr expr) {
    debug(CodeGen) log("AssignExpr", expr);

    StructDecl owner = findOwnerDecl(expr.left);
    string target = expr.left.findTarget();
    auto modules = findModules(expr.right);

    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

    if (cast(ModuleDecl)owner !is null) {
      if (!owner.external) {
        emit(expr.left.lvalueToString());
        emit("__dg = ");
        emit("null;\n");
      }
    }

    foreach(mod; modules) {
      if (mod == "this") continue;
      emit(mod);
      emit("._tick(); ");
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

  void visit(IndexExpr expr) {
    debug(CodeGen) log("IndexExpr");

    accept(expr.expr);
    emit("[");
    accept(expr.arguments);
    emit("]");
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

    VarDecl varDecl = cast(VarDecl)stmt.decl;
    if (varDecl.external) return;

    string typeName = stmt.decl.declType.typeString();
    emit(typeName);
    emit(" ");
    emit(stmt.identifier.value);
    if (stmt.expr) {
      emit(" = ");
      accept(stmt.expr);
    }
    emit(";\n");

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
    emit(expr.decl.visit!(
      (Decl d) => d.name.value,
      (TypeDecl d) => typeString(d.declType)
    ));
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

  void visit(ReturnStmt returnStmt) {
    emit("return ");
    accept(returnStmt.expr);
    emit(";\n");
  }

  void visit(FunctionDecl funcDecl) {
    debug(CodeGen) log("FunctionDecl", funcDecl.name.value);
    if (!funcDecl.external) {
      if (funcDecl.returnExpr)
        accept(funcDecl.returnExpr);
      else
        emit("void");
      emit(" ");
      emit(funcDecl.name.value);
      emit("(");
      for (int i = 0; i < funcDecl.parameterTypes.length; ++i) {
        accept(funcDecl.parameterTypes[i]);
        emit(" ");
        emit(funcDecl.parameterIdentifiers[i]);
        if (i + 1 < funcDecl.parameterTypes.length) {
          emit(", ");
        }
      }
      emit(") ");
      //emit("{");
      accept(funcDecl.functionBody);
    }
  }

  void visit(StructDecl structDecl) {
   debug(CodeGen) log("StructDecl", structDecl.name.value);
   if (!structDecl.external) {
     assert(false, "Structs not yet supported");
   }
  }

  void visit(ModuleDecl moduleDecl) {
    debug(CodeGen) log("ModuleDecl", moduleDecl.name.value);
    if (!moduleDecl.external) {
        emit("struct ");
        emit(moduleDecl.name.value);
        emit(" {");
        indent();
        emit("\n");
        foreach(field ; moduleDecl.decls.symbolsInDefinitionOrder) {
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

        foreach(field ; moduleDecl.decls.symbolsInDefinitionOrder) {
          if (auto fd = cast(FieldDecl)field) {
            emit("if (");
            emit(fd.name.value);
            emit("__dg) ");
            emit(fd.name.value);
            emit("__dg();\n");
          }
        }
        if (moduleDecl.decls.defines("tick")) {
          emit("tick();");
        }
        outdent();
        emit("\n}");
        outdent();
        emit("\n}\n\n");
    }
  }

  void visit(ImportStmt importStatement) {
    line(importStatement);
    emit("import ");
    emit(importStatement.targetContext.moduleName);
    emit(";\n");
  }

  void visit(Library library) {
    debug(CodeGen) log("Library");

    foreach (i, node; library.declarations) {
      accept(node);
    }

    //emit ("void start() {\n");

    emit("struct MainModule {");
    indent();
    emit("\n\nvoid run() {\n");
    indent();
    foreach (i, node; library.nodes) {
      if (cast(TypeDeclStmt)node is null)
        accept(node);
    }
    outdent();
    emit("\n}");
    outdent();
    emit("\n}");
  }
};
