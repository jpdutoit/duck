module duck.compiler.backend.d.codegen;

//debug = CodeGen;

import duck.compiler.ast;
import duck.compiler.lexer.tokens;
import duck.compiler.types;
import duck.compiler.transforms;
import duck.compiler;
import duck.compiler.context;
import duck.compiler.visitors;
import duck.compiler.semantic.helpers;

import duck.compiler.dbg;
import duck.compiler.backend.d.appender;

immutable PREAMBLE = q{
  import duck.runtime, duck.stdlib, core.stdc.stdio : printf;

};
immutable POSTAMBLE_MAIN = q{

      void main(string[] args) {
        initialize(args);
        MainModule m;
        Duck(&m.run);
        Scheduler.run();
      }
};

//  This code generator is a bit of hack at the moment

string generateCode(Node node, Context context, bool isMainFile) {
  CodeGen cg = CodeGen(context);
  node.accept(cg);

  auto code = cg.output.data;
  return isMainFile
      ? PREAMBLE ~ code ~ POSTAMBLE_MAIN
      : PREAMBLE ~ code;
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
    (RefExpr re) => re.context
      ? lvalueToString(re.context) ~ "." ~ re.decl.name
      : re.decl.name,
    (IdentifierExpr ie) => ie.identifier);
}

string findTarget(Expr expr) {
  return expr.visit!(
    (Expr expr) => cast(string)null,
    (RefExpr expr) => expr.context ? lvalueToString(expr.context) : null);
}

StructDecl findOwnerDecl(Expr expr) {
  return expr.visit!(
    (Expr expr) => cast(StructDecl)null,
    (RefExpr e) {
      if (e.context) {
        if (auto ge = cast(ModuleType)e.context.exprType) {
          return ge.decl;
        }
        return e.context.findOwnerDecl();
      }
      return null;
    });
}

auto findModules(Expr expr) {
  string[] modules;
  expr.traverse((RefExpr e) {
    if (e.context && e.context.exprType.kind == ModuleType.Kind) {
      modules ~= e.findTarget();
      //return false;
    }
    return true;
  });

  return modules;
}

struct CodeGen {
  DAppender!CodeGen output;

  Context context;

  string[size_t] symbols;
  int symbolCount = 0;

  string symbolName(Decl decl) {
    import std.conv : to;
    size_t addr = cast(size_t)cast(void*)decl;
    string* name = addr in symbols;
    if (name is null) {
      symbolCount++;
      string s = "__symbol_" ~ symbolCount.to!string();
      symbols[addr] = s;
      debug(CodeGen) log("symbolName", mangled(decl.declType), s, decl.name.toString());
      return s;
    }
    debug(CodeGen) log("symbolName", mangled(decl.declType), *name,decl.name.toString());
    return *name;
  }

  this(Context context) {
    this.context = context;
    this.output = DAppender!CodeGen(&this);
  }

  void accept(Node n) {
    debug(CodeGen) {
      logIndent();
      log(n.prettyName.red, n);
    }
    n.accept(this);
    debug(CodeGen) logOutdent();
  }

  void visit(IdentifierExpr expr) {
    output.put(expr.identifier);
  }

  void visit(LiteralExpr expr) {
    output.put(expr.value);
  }

  void visit(ArrayLiteralExpr expr) {
    output.expression("[", expr.exprs, "]");
  }

  void visit(BinaryExpr expr) {
    output.expression(expr.left, expr.operator.value, expr.right);
  }

  void instrument(Expr value, Expr target) {
    auto slice = value.source;
    output.statement("instrument(\"", slice.toLocationString(), ": ", slice.toString(), "\", cast(void*)&", target, ", ", value, ");");
  }

  void visit(PipeExpr expr) {
    auto modules = findModules(expr.left);

    if (modules.length == 0) {
      debug(CodeGen) log("=> Rewrite as:");
      accept(new AssignExpr(context.token(Tok!"=", "="), expr.right, expr.left));
      return;
    }

    StructDecl owner = findOwnerDecl(expr.right);
    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

    if ((cast(ModuleDecl)owner is null)) {
      output.statement(expr.right, " = ", expr.left, ";");
      return;
    }

    if (owner.external)
      output.statement(expr.right.findTarget(), ".__add( () ");
    else
      output.statement(expr.right.lvalueToString(), "__dg = ()");

    output.block(() {
      foreach(mod; modules)
        output.statement(mod, "._tick();");

      output.statement(expr.right, " = ", expr.left, ";");
      if (context.instrument) instrument(expr.left, expr.right);
    });

    if (owner.external)
      output.put(")");
  }

  void visit(AssignExpr expr) {
    StructDecl owner = findOwnerDecl(expr.left);
    auto modules = findModules(expr.right);

    debug(CodeGen) if (owner) log("=> Property Owner:", owner.name);

    if (cast(ModuleDecl)owner !is null) {
      if (!owner.external) {
        output.statement(expr.left.lvalueToString(), "__dg = null;");
      }
    }

    foreach(mod; modules) {
      if (mod == "this") continue;
      output.statement(mod, "._tick(); ");
    }

    output.statement(expr.left, expr.operator.value, expr.right);
  }

  void visit(UnaryExpr expr) {
    output.expression(expr.operator.value, expr.operand);
  }

  void visit(TupleExpr expr) {
    output.put(expr.elements);
  }

  void visit(IndexExpr expr) {
    output.put(expr.expr, "[", expr.arguments, "]");
  }

  void visit(ConstructExpr expr) {
    auto callable = expr.callable.enforce!RefExpr().decl.as!CallableDecl;
    if (callable.isExternal) {
      output.put(callable.parentDecl.declType.typeString(), "(", expr.arguments, ")");
    } else {
      output.put(callable.parentDecl.declType.typeString(), "().", expr.callable, "(", expr.arguments, ")");
    }
  }
  void visit(CallExpr expr) {
    auto callable = expr.callable.enforce!RefExpr().decl.as!CallableDecl;
    if (callable.isExternal && callable.isOperator && expr.arguments.length == 2) {
      output.expression(expr.arguments[0], expr.callable, expr.arguments[1]);
    } else {
      output.put(expr.callable, "(", expr.arguments, ")");
    }
  }

  void visit(VarDecl decl) {
    if (decl.external) return;

    string typeName = decl.declType.typeString();
    Expr value = decl.valueExpr ? decl.valueExpr.visit!(
      (ConstructExpr c) => (c.callable ? c : null),
      (Expr e) => e)
      : null;

    if (value)
      output.statement(typeName, " ", decl.name, "=", value, ";");
    else
      output.statement(typeName, " ", decl.name, ";");
  }

  void visit(VarDeclStmt stmt) {
    accept(stmt.decl);
  }

  void visit(TypeDeclStmt stmt) {
    accept(stmt.decl);
  }

  void visit(ExprStmt stmt) {
    output.statement(stmt.expr, ";");
  }

  void visit(IfStmt stmt) {
    auto modules = findModules(stmt.condition);

    foreach(mod; modules) {
      if (mod == "this") continue;
      output.statement(mod, "._tick(); ");
    }

    output.ifStatement(stmt.condition, stmt.trueBody);
    output.elseStatement(stmt.falseBody);
  }

  void line(Node node) {
    auto slice = node.source;
    if (cast(FileBuffer)slice.buffer) {
      import std.conv : to;
      output.line(slice.lineNumber, slice.buffer.name);
    } else {
      output.line(0, null);
    }
  }

  void visit(Stmts expr) {
    foreach (i, Stmt stmt; expr.stmts) {
      if (!cast(Stmts)stmt) line(stmt);
      accept(stmt);
    }
  }

  void visit(TypeExpr expr) {
    output.put(expr.expr);
  }

  void visit(RefExpr expr) {
    auto name = expr.decl.visit!(
      (Decl d) => d.name,
      (CallableDecl d) => d.isExternal ? d.name : symbolName(d),
      (TypeDecl d) => typeString(d.declType)
    );

    if (expr.context)
      output.put(expr.context, ".", name);
    else
      output.put(name);
  }

  void visit(ScopeStmt expr) {
    output.block(() {
      accept(expr.stmts);
    });
  }

  void visit(ParameterDecl decl) {
    output.put(decl.name);
  }

  void visit(FieldDecl fieldDecl) {

    if (fieldDecl.declType.as!ModuleType is null)
      output.statement("__ConnDg ", fieldDecl.name, "__dg; ");

    visit(cast(VarDecl)fieldDecl);
  }

  void visit(ReturnStmt returnStmt) {
    output.statement("return ", returnStmt.expr, ";");
  }

  void visit(CallableDecl funcDecl) {
    if (funcDecl.isMacro) return;

    if (!funcDecl.isExternal) {
      auto name = symbolName(funcDecl);
      if (funcDecl.isConstructor)
        output.functionDecl(funcDecl.parentDecl.name, name);
      else if (funcDecl.returnExpr)
        output.functionDecl(funcDecl.returnExpr, name);
      else
        output.functionDecl("void", name);

      foreach (i, parameter; funcDecl.parameters)
        output.functionArgument(parameter.as!ParameterDecl().typeExpr, parameter.name);

      output.functionBody(() {
        accept(funcDecl.callableBody);
        if (funcDecl.isConstructor)
          output.statement("return this;");
      });
    }
  }

  void visit(StructDecl structDecl) {
   if (!structDecl.external) {
     assert(false, "Structs not yet supported");
   }
  }

  void visit(ModuleDecl moduleDecl) {
    if (!moduleDecl.external) {
        output.structDecl(moduleDecl.name, () {
          foreach(field ; moduleDecl.decls.symbolsInDefinitionOrder) accept(field);
          foreach(ctor ; moduleDecl.ctors.decls) accept(ctor);

          output.statement("ulong __sampleIndex = ulong.max;");

          output.functionDecl("void", "_tick");
          output.functionBody((){
            output.statement("if (__sampleIndex == __idx) return;");
            output.statement("__sampleIndex = __idx;");

            foreach(field ; moduleDecl.decls.symbolsInDefinitionOrder) {
              if (auto fd = cast(FieldDecl)field) {
                if (fd.declType.as!ModuleType is null) {
                  output.statement("if (", fd.name, "__dg) ", fd.name, "__dg();");
                }
              }
            }
            if (auto os = moduleDecl.decls.lookup("tick").as!OverloadSet) {
              output.statement(symbolName(os.decls[0]), "();");
            }
          });
        });
    }
  }

  void visit(ImportStmt importStatement) {
    line(importStatement);
    output.statement("import ", importStatement.targetContext.moduleName, ";");
  }

  void visit(Library library) {
    foreach (i, node; library.declarations) accept(node);

    output.structDecl("MainModule", () {
      output.functionDecl("void", "run");
      output.functionBody(library.stmts);
    });
  }
};
