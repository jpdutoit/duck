module duck.compiler.backend.d.codegen;

//debug = CodeGen;

import duck.compiler.ast;
import duck.compiler.lexer.tokens;
import duck.compiler.types;
import duck.compiler;
import duck.compiler.context;
import duck.compiler.visitors;
import duck.compiler.semantic.helpers;

import duck.compiler.dbg;
import duck.compiler.backend.d.appender;
import duck.compiler.backend.d.optimizer;

//  This code generator is a bit of hack at the moment

CallableDecl callableDecl(CallExpr expr) {
  return expr.callable.enforce!RefExpr().decl.enforce!CallableDecl;
}

class CodeGenContext {
  Context context;
  alias context this;

  Optimizer metrics;

  this(Context root) {
    this.context = root;
    this.metrics = new Optimizer(root.library);
  }

  private {
    string[Decl] uniqueNames;
    int declCount = 0;
  }

  final string uniqueName(Decl decl) {
    import std.conv : to;
    string* name = decl in uniqueNames;
    if (name is null) {
      declCount++;
      string s = "__symbol_" ~ declCount.to!string();
      uniqueNames[decl] = s;
      debug(CodeGen) log("symbolName", s, decl, decl.name.toString());
      return s;
    }
    debug(CodeGen) log("symbolName", *name,decl.name.toString());
    return *name;
  }
}

string generateCode(Node node, CodeGenContext context) {
  auto cg = CodeGen(context);
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
  CodeGenContext context;
  DAppender!CodeGen output;
  Stack!Node stack;

  string name(Type type) {
    import std.conv: to;
    return type.visit!(
      (ModuleType m) => m.name,
      (StructType t) => t.name,
      (StringType t) => "string",
      (FloatType t) => "float",
      (IntegerType t) => "int",
      (BoolType t) => "bool",
      (ArrayType t) => name(t.elementType) ~ "[]",
      (StaticArrayType t) => name(t.elementType) ~ "[" ~ t.size.to!string ~ "]"
    );
  }

  string name(Decl decl) {
    return decl.visit!(
      (ParameterDecl d) => d.name,
      (BuiltinVarDecl d) => d.name,
      (VarDecl d) => d.isExternal ? d.name : context.uniqueName(d),
      (FieldDecl d) => d.name, //d.parentDecl.external ? d.name : context.uniqueName(d),
      (CallableDecl d) {
        if (d.isExternal) {
          return d.isConstructor ? "initialize" : d.name;
        }
        return context.uniqueName(d);
      },
      (TypeDecl d) => name(d.declaredType),
      (Decl d) => context.uniqueName(d)
    );
  }

  auto metrics() { return context.metrics; }
  this(CodeGenContext codeGenContext) {
    this.context = codeGenContext;
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
      accept(new AssignExpr(Slice("="), expr.right, expr.left));
      return;
    }

    ModuleDecl typeDecl = targetModule.moduleDecl;
    debug(CodeGen) if (typeDecl) log("=> Property Owner:", typeDecl.name);

    if (!metrics.isDynamicField(expr.right.findField())) {
      output.statement(expr.right, " = ", expr.left);
      return;
    }

    if (typeDecl.isExternal)
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

    if (typeDecl.isExternal)
      output.put(")");
  }

  void visit(AssignExpr expr) {
    auto ownerDecl = expr.left.findModuleContext().moduleDecl;
    ModuleDecl thisDecl = stack.find!ModuleDecl;

    auto modules = findModules(expr.right);

    debug(CodeGen) if (ownerDecl) log("=> Property Owner:", ownerDecl.name);

    if (metrics.isDynamicField(expr.left.findField())) {
      if (!ownerDecl.isExternal && expr.left.as!RefExpr) {
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

  void visit(CastExpr expr) {
    if ((expr.sourceType.as!IntegerType && expr.targetType.as!FloatType) ||
        (expr.sourceType.as!BoolType && (expr.targetType.as!IntegerType || expr.targetType.as!FloatType)))
      output.expression(expr.expr);
    else
      output.expression("cast(", name(expr.targetType), ")", expr.expr);
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
      (FloatType t) => output.put("0"),
      (IntegerType t) => output.put("0"),
      (BoolType t) => output.put("false"),
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
      if (expr.arguments.length == 0)
        putDefaultValue(expr.type);
      else {
        output.put(typeName, "(", expr.arguments, ")");
      }
      return;
    }

    auto callable = expr.callableDecl;
    if (expr.type.isModule || !callable.isExternal)
      output.put(typeName, ".alloc().", expr.callable, "(", expr.arguments, ")");
    else
      output.put(typeName, "(", expr.arguments, ")");
  }

  void visit(CallExpr expr) {
    auto callable = expr.callableDecl;
    if (callable.isExternal && callable.isOperator) {
      auto re = expr.callable.enforce!RefExpr;
      if (re.decl.name == "[]" && re.context) {
        output.expression(re.context, "[", expr.arguments, "]");
      } else if (expr.arguments.length == 2) {
        output.expression(expr.arguments[0], expr.callable, expr.arguments[1]);
      } else {
        context.error(expr.source, "Interal compiler error");
      }
    } else {
      output.put(expr.callable, "(", expr.arguments, ")");
    }
  }

  void visit(VarDecl decl) {
    if (decl.isExternal) return;

    output.statement(name(decl.type), decl.type.isModule ? "* " : " ", name(decl), " = ");
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

  void visit(RefExpr expr) {
    auto name = name(expr.decl);

    if (expr.context)
      output.put(expr.context, ".", name);
    else
      output.put(name);
  }

  void visit(BlockStmt stmt) {
    foreach(s; stmt) {
      line(s);
      accept(s);
    }
  }

  void visit(ScopeStmt stmt) {
    output.block(() {
      visit(stmt.enforce!BlockStmt);
    });
  }

  void visit(ParameterDecl decl) {
    output.put(decl.type.isModule ? "* " : " ", name(decl));
  }

  void visit(FieldDecl field) {
    if (!metrics.isReferenced(field)) return;
    if (metrics.isDynamicField(field))
      output.statement("__ConnDg ", name(field), "__dg = void; ");

    output.statement(name(field.type), field.type.isModule ? "* " : " ", name(field), " = void;");
  }

  void visit(ReturnStmt returnStmt) {
    output.statement("return ", returnStmt.value, ";");
  }

  void visit(CallableDecl funcDecl) {
    if (funcDecl.isMacro) return;

    if (!funcDecl.isExternal) {

      if (!funcDecl.parent) {
        output.statement("static");
      }

      auto callableName = name(funcDecl);
      if (funcDecl.isConstructor) {
        if (funcDecl.parent.declaredType.isModule)
          output.functionDecl(name(funcDecl.parent) ~ "* ", callableName);
        else
          output.functionDecl(name(funcDecl.parent), callableName);
      }
      else if (funcDecl.returnExpr)
        output.functionDecl(funcDecl.returnExpr, callableName);
      else
        output.functionDecl("void", callableName);

      foreach (i, parameter; funcDecl.parameters)
        output.functionArgument(parameter.as!ParameterDecl().typeExpr, name(parameter));

      output.functionBody(() {
        accept(funcDecl.callableBody);
        if (funcDecl.isConstructor) {
          if (funcDecl.parent.declaredType.isModule)
            output.statement("return &this;");
          else
            output.statement("return this;");
        }
      });
    }
  }

  void visit(StructDecl structDecl) {
    if (!structDecl.isExternal) {
      assert(false, "Structs not yet supported");
    }
  }

  void visit(ModuleDecl moduleDecl) {
    if (!metrics.isReferenced(moduleDecl)) return;
    if (!moduleDecl.isExternal) {
        output.statement("static");
        output.structDecl(name(moduleDecl), () {
          if (metrics.hasDynamicFields(moduleDecl))
            output.statement("ulong __sampleIndex = void;");

          foreach(field ; moduleDecl.members.all) accept(field);

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
            foreach(field; moduleDecl.members.fields.as!FieldDecl) {
              if (!metrics.isReferenced(field)) continue;
              if (metrics.isDynamicField(field))
                output.statement("instance.", name(field), "__dg = null;");
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

              foreach(field; moduleDecl.members.fields.as!FieldDecl) {
                if (!metrics.isReferenced(field)) continue;
                if (metrics.isDynamicField(field)) {
                  output.statement("if (", name(field), "__dg) ", name(field), "__dg();");
                }
              }
              if (auto os = moduleDecl.members.lookup("tick").as!OverloadSet) {
                output.statement(name(os.decls[0]), "();");
              }
            });
          }
        });
    }
  }

  void visit(ImportStmt importStatement) {
    if (importStatement.targetContext.type != ContextType.builtin)
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
      foreach (stmt; library.stmts)
        if (stmt.as!DeclStmt)
          accept(stmt);
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
