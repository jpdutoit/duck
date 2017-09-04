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
import duck.compiler.backend.d.optimizer;

//  This code generator is a bit of hack at the moment

string generateCode(Node node, Optimizer metrics) {
  auto cg = CodeGen(context, metrics);
  node.accept(cg);
  return cg.output.data;
}

ModuleDecl moduleDecl(RefExpr expr) {
  if (expr)
  if (auto mt = expr.type.as!ModuleType)
    return mt.decl;
  return null;
}

auto findModules(Expr expr) {
  return expr.traverseCollect!(
    (RefExpr r) => r.context && r.context.type.isModule ? r.context.as!RefExpr : null
  );
}

RefExpr findModuleContext(Expr expr) {
  return expr.traverseFind!(
    (RefExpr e) => e.context && e.context.type.isModule ? e.context.as!RefExpr : null
  );
}

auto findField(Expr expr) {
  return expr.traverseFind!((RefExpr e) => e.decl.as!FieldDecl);
}

struct CodeGen {
  DAppender!CodeGen output;

  Optimizer metrics;
  Stack!Node stack;

  Context context;

  string[Decl] symbols;
  int symbolCount = 0;

  string symbolName(Decl decl) {
    import std.conv : to;
    string* name = decl in symbols;
    if (name is null) {
      symbolCount++;
      string s = "__symbol_" ~ symbolCount.to!string();
      symbols[decl] = s;
      debug(CodeGen) log("symbolName", s, decl.name.toString());
      return s;
    }
    debug(CodeGen) log("symbolName", *name,decl.name.toString());
    return *name;
  }

  string name(Type type) {
    import std.conv: to;
    return type.visit!(
      (ModuleType m) => m.name,
      (StructType t) => t.name,
      (StringType t) => "string",
      (NumberType t) => "float",
      (ArrayType t) => name(t.elementType) ~ "[]",
      (StaticArrayType t) => name(t.elementType) ~ "[" ~ t.size.to!string ~ "]"
    );
  }

  string name(Decl decl) {
    return decl.visit!(
      (Decl d) => d.name,
      (CallableDecl d) {
        if (d.isExternal) {
          return d.isConstructor ? "initialize" : d.name;
        }
        return symbolName(d);
      },
      (TypeDecl d) => name(d.declaredType)
    );
  }

  this(Context context, Optimizer metrics) {
    this.metrics = metrics;
    this.context = context;
    this.output = DAppender!CodeGen(&this);
  }

  void accept(Node n) {
    debug(CodeGen) {
      logIndent();
      log(n.prettyName.red, n);
    }
    stack.push(n);
    n.accept(this);
    stack.pop();
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
    auto targetModule = expr.right.findModuleContext();
    auto modules = findModules(expr.left);

    if (modules.length == 0) {
      debug(CodeGen) log("=> Rewrite as:");
      accept(new AssignExpr(context.token(Tok!"=", "="), expr.right, expr.left));
      return;
    }

    ModuleDecl typeDecl = targetModule.moduleDecl;
    debug(CodeGen) if (typeDecl) log("=> Property Owner:", typeDecl.name);

    if (!metrics.isDynamicField(expr.right.findField())) {
      output.statement(expr.right, " = ", expr.left);
      return;
    }

    if (typeDecl.external)
      output.statement(targetModule, ".__add( () ");
    else
      output.statement(expr.right, "__dg = ()");

    output.block(() {
      foreach(mod; modules) {
        if (targetModule.decl != mod.decl && metrics.hasDynamicFields(mod.type.as!ModuleType.decl))
          output.statement(mod, "._tick();");
      }

      output.statement(expr.right, " = ", expr.left, ";");
      if (context.options.instrument) instrument(expr.left, expr.right);
    });

    if (typeDecl.external)
      output.put(")");
  }

  void visit(AssignExpr expr) {
    auto ownerDecl = expr.left.findModuleContext().moduleDecl;
    ModuleDecl thisDecl = stack.find!ModuleDecl;

    auto modules = findModules(expr.right);

    debug(CodeGen) if (typeDecl) log("=> Property Owner:", typeDecl.name);

    if (metrics.isDynamicField(expr.left.findField())) {
      if (!ownerDecl.external) {
        output.statement(expr.left, "__dg = null;");
      }
    }
    foreach(mod; modules) {
      auto modDecl = mod.moduleDecl;
      if ((thisDecl !is modDecl) && (ownerDecl != modDecl) && metrics.hasDynamicFields(modDecl))
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

  void putDefaultValue(Type type) {
    type.visit!(
      (ModuleType t) => output.put(name(type), ".alloc()"),
      (StructType t) => output.put(name(type), ".init"),
      (StringType t) => output.put("\"\""),
      (NumberType t) => output.put("0"),
      (ArrayType t) => output.put("[]"),
      (StaticArrayType t) {
        output.put("[");
        for (int i = 0; i < t.size; i++) {
          if (i > 0) output.put(", ");
          putDefaultValue(t.elementType);
        }
        output.put("]");
      }
    );
  }

  void visit(ConstructExpr expr) {
    auto typeName = name(expr.type);

    // Default construction
    if (!expr.callable) {
      putDefaultValue(expr.type);
      return;
    }

    auto callable = expr.callable.enforce!RefExpr().decl.as!CallableDecl;
    if (expr.type.isModule || !callable.isExternal)
      output.put(typeName, ".alloc().", expr.callable, "(", expr.arguments, ")");
    else
      output.put(typeName, "(", expr.arguments, ")");
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

    output.statement(name(decl.type), decl.type.isModule ? "* " : " ", decl.name, " = ");
    if (decl.valueExpr)
      output.put(decl.valueExpr, ";");
    else
      output.put("void;");
  }

  void visit(DeclStmt stmt) {
    accept(stmt.decl);
  }

  void visit(ExprStmt stmt) {
    output.statement(stmt.expr, ";");
  }

  void visit(IfStmt stmt) {
    auto modules = findModules(stmt.condition);

    foreach(mod; modules) {
      //if (mod == "this") continue;
      if (metrics.hasDynamicFields(mod.type.as!ModuleType.decl))
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
    auto name = name(expr.decl);

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
    output.put(decl.type.isModule ? "* " : " ", name(decl));
  }

  void visit(FieldDecl field) {
    if (!metrics.isReferenced(field)) return;
    if (metrics.isDynamicField(field))
      output.statement("__ConnDg ", field.name, "__dg = void; ");

    output.statement(name(field.type), field.type.isModule ? "* " : " ", field.name, " = void;");
  }

  void visit(ReturnStmt returnStmt) {
    output.statement("return ", returnStmt.expr, ";");
  }

  void visit(CallableDecl funcDecl) {
    if (funcDecl.isMacro) return;

    if (!funcDecl.isExternal) {

      if (!funcDecl.parentDecl) {
        output.statement("static");
      }

      auto callableName = name(funcDecl);
      if (funcDecl.isConstructor) {
        if (funcDecl.parentDecl.declaredType.isModule)
          output.functionDecl(name(funcDecl.parentDecl) ~ "* ", callableName);
        else
          output.functionDecl(name(funcDecl.parentDecl), callableName);
      }
      else if (funcDecl.returnExpr)
        output.functionDecl(funcDecl.returnExpr, callableName);
      else
        output.functionDecl("void", callableName);

      foreach (i, parameter; funcDecl.parameters)
        output.functionArgument(parameter.as!ParameterDecl().typeExpr, parameter.name);

      output.functionBody(() {
        accept(funcDecl.callableBody);
        if (funcDecl.isConstructor) {
          if (funcDecl.parentDecl.declaredType.isModule)
            output.statement("return &this;");
          else
            output.statement("return this;");
        }
      });
    }
  }

  void visit(StructDecl structDecl) {
    if (!structDecl.external) {
      assert(false, "Structs not yet supported");
    }
  }

  void visit(ModuleDecl moduleDecl) {
    if (!metrics.isReferenced(moduleDecl)) return;
    if (!moduleDecl.external) {

        output.statement("static");
        output.structDecl(moduleDecl.name, () {
          if (metrics.hasDynamicFields(moduleDecl))
            output.statement("ulong __sampleIndex = void;");

          foreach(field ; moduleDecl.decls.symbolsInDefinitionOrder) accept(field);
          foreach(ctor ; moduleDecl.ctors.decls) accept(ctor);

          auto typeName = name(moduleDecl);
          output.functionDecl("static auto", "alloc");
          output.functionBody((){
            output.statement("return alloc(new ", typeName, "());");
          });

          output.functionDecl("static auto", "alloc");
          output.functionArgument(typeName ~ "*", "instance");
          output.functionBody((){
            if (metrics.hasDynamicFields(moduleDecl))
              output.statement("instance.__sampleIndex = ulong.max;");
            foreach(field; moduleDecl.decls.fields) {
              if (!metrics.isReferenced(field)) continue;
              if (metrics.isDynamicField(field))
                output.statement("instance.", field.name, "__dg = null;");
              if (auto value = field.valueExpr)
                output.statement("instance.", name(field), " = ", value, ";");
            }
            output.statement("return instance;");
          });

          if (metrics.hasDynamicFields(moduleDecl)) {
            output.functionDecl("void", "_tick");
            output.functionBody((){
              output.statement("if (__sampleIndex == __idx) return;");
              output.statement("__sampleIndex = __idx;");

              foreach(field; moduleDecl.decls.fields) {
                if (!metrics.isReferenced(field)) continue;
                if (metrics.isDynamicField(field)) {
                  output.statement("if (", field.name, "__dg) ", field.name, "__dg();");
                }
              }
              if (auto os = moduleDecl.decls.lookup("tick").as!OverloadSet) {
                output.statement(symbolName(os.decls[0]), "();");
              }
            });
          }
        });
    }
  }

  void visit(ImportStmt importStatement) {
    line(importStatement);
    output.statement("import ", importStatement.targetContext.moduleName, ";");
  }

  void visit(Library library) {
    if (context.isMain) {
      output.put(PREAMBLE);
      output.functionDecl("void", "run");
      output.functionBody(library.stmts);
      output.put(POSTAMBLE_MAIN);
    } else {
      output.put(PREAMBLE);
      foreach (i, node; library.declarations)
        accept(node);
    }
  }
};


private immutable PREAMBLE = q{
  import duck.runtime, duck.stdlib, core.stdc.stdio : printf;
};

private immutable POSTAMBLE_MAIN = q{
      void main(string[] args) {
        initialize(args);
        Duck(&run);
        Scheduler.run();
      }
};
