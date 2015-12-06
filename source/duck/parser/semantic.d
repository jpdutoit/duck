module duck.compiler.semantic;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types, duck.compiler.transforms;
import duck.compiler.visitors, duck.compiler.context;
import duck.compiler.scopes;
import duck.compiler;

alias String = const(char)[];

//debug = Semantic;

struct OperatorTypeMap
{
  alias TypeType = Type[Type];
  alias TypeTypeType = TypeType[Type];
  TypeTypeType[String] binary;

  void set(Type a, String op, Type b, Type c) {
    binary[op][a][b]=c;
  }
  Type get(Type a, String op, Type b) {
    if (op in binary) {
      TypeTypeType t3 = binary[op];
      if (a in t3) {
        TypeType t2 = t3[a];
        if (b in t2) {
          return t2[b];
        }
      }
    }
    return null;
  }
}

bool hasError(Expr expr) {
  return expr.exprType == errorType;
}

bool hasType(Expr expr) {
  return expr._exprType !is null;
}

auto taint(Expr expr) {
  expr.exprType = errorType;
  return expr;
}
auto taint(Decl decl) {
  decl.declType = errorType;
  return decl;
}


class SemanticAnalysis : TransformVisitor {

  debug(Semantic) {
    enum string PAD = "                                                                                ";
    static string padding(int __depth) { return PAD[0..__depth*4]; }

    void log(T...)(string where, T t) {
      import std.stdio : write, writeln;
      write(padding(depth), where, " ");
      foreach(tt; t) {
        write(" ", tt);
      }
      writeln();
    }
  }

  OperatorTypeMap typeMap;

  SymbolTable symbolTable;
  Scope globalScope;
  string sourcePath;
  //SymbolTable globalScope;
  //SymbolTable[] scopes;

  Context context;

  int errors = 0;

  this(Context context, string sourcePath) {
    this.symbolTable = new SymbolTable();
    this.context = context;
    this.sourcePath = sourcePath;
  }

  Type type(string t) {
    Decl decl = symbolTable.lookup(t);
    return decl.declType;
  }

  void init() {
    //typeMap.set(numberType, "+", numberType, numberType);
    typeMap.set(numberType, "*", numberType, numberType);
    typeMap.set(numberType, "+", numberType, numberType);
    typeMap.set(numberType, "-", numberType, numberType);
    typeMap.set(numberType, "/", numberType, numberType);
    typeMap.set(numberType, "%", numberType, numberType);
    typeMap.set(type("Time"), "%", type("Duration"), type("Duration"));
    //typeMap.set(type("Duration"), "+", numberType, numberType);
    typeMap.set(numberType, "*", type("Duration"), type("Duration"));
    typeMap.set(type("Duration"), "+", type("Duration"), type("Duration"));
    typeMap.set(type("Duration"), "-", type("Duration"), type("Duration"));

    typeMap.set(type("Duration"), "*", numberType, type("Duration"));
    typeMap.set(type("frequency"), "*", numberType, type("frequency"));
    typeMap.set(type("frequency"), "/", numberType, type("frequency"));
    typeMap.set(type("frequency"), "/", type("frequency"), numberType);
    typeMap.set(type("frequency"), "+", type("frequency"), type("frequency"));
    typeMap.set(type("frequency"), "-", type("frequency"), type("frequency"));
    typeMap.set(numberType, "*", type("frequency"), type("frequency"));
  }

  bool isLValue(Expr expr) {
    if (!!cast(RefExpr)expr) return true;
    if (auto memberExpr = cast(MemberExpr)expr) {
      return isLValue(memberExpr.expr);
    }
    return false;
  }

  int pipeDepth = 0;


  static bool isGenerator(Expr expr) {
    return expr.exprType.kind == GeneratorType.Kind;
  }

  Expr makeGenerator(Type type, Expr ctor) {
    auto t = context.temporary();
    return new InlineDeclExpr(t, new DeclStmt(t, new VarDecl(type, t), ctor));
  }

  void implicitConstruct(ref Expr expr) {
    //writefln("implicitConstruct %s", expr.accept(ExprToString()));
    // Rewrite: Generator
    // to:      Generator tmpVar = Generator();
    if (expr.exprType == typeType) {
      if (auto refExpr = cast(RefExpr)expr) {
        if (refExpr.decl.declType.kind == GeneratorType.Kind) {
          auto ctor = new CallExpr(refExpr, []);
          expr = makeGenerator(refExpr.decl.declType, ctor);
          accept(expr);
          return;
        }
      }
    }
    // Rewrite: Expr that returns a Generator
    // to:      Generator tmpVar = expr;
    if (expr.exprType.isKindOf!GeneratorType && !isLValue(expr)) {
      expr = makeGenerator(expr.exprType, expr);
      accept(expr);
    }
  }

  Stmt[] splitStatements;

  void error(Expr expr, string message) {
    context.error(expr.accept(LineNumber()), message);
  }

  void error(Token token, string message) {
    context.error(token.span, message);
  }

  alias visit = TransformVisitor.visit;



  override Node visit(InlineDeclExpr expr) {
    debug(Semantic) log("InlineDeclExpr", expr.print);
    accept(expr.declStmt);

    splitStatements ~= expr.declStmt;
    //debug(Semantic) writefln("InlineDeclExpr2 %s", expr.declStmt);
    Expr ident = new IdentifierExpr(expr.token);
    accept(ident);
    debug(Semantic) log("=>", ident.print);
    //debug(Semantic) writefln("InlineDeclExpr3 %s", ident);

    return ident;
  }

  override Node visit(ExprStmt stmt) {
    debug(Semantic) log("ExprStmt", stmt.expr.print);
    if (auto declExpr = cast(InlineDeclExpr) stmt.expr) {
      accept(declExpr.declStmt);
      return declExpr.declStmt;
    }

    splitStatements = [];
    accept(stmt.expr);
    debug(Semantic) log("=>", stmt.expr.print);
    if (splitStatements.length > 0) {
      return new Stmts(splitStatements ~ stmt);
    }
    return stmt;
  }
  /*override Node visit(ExprStmt expr) {
    accept(expr.expr);
    return expr;
  }*/

  override Node visit(ArrayLiteralExpr expr) {
    debug(Semantic) log("ArrayLiteralExpr", expr.print);
    Type elementType;
    foreach(ref e; expr.exprs) {
      accept(e);
      if (!elementType) {
        elementType = e.exprType;
      } else if (elementType != e.exprType) {
        error(e, "Expected array element to have type " ~ elementType.mangled);
      }
    }
    expr.exprType = new ArrayType(expr.exprs[0].exprType);
    debug(Semantic) log("=>", expr.print);
    return expr;
  }

  override Node visit(PipeExpr expr) {
    debug(Semantic) log("PipeExpr");
    debug(Semantic) log("=>", expr.print);
    pipeDepth++;
    accept(expr.left);
    debug(Semantic) log("=>", expr.print);
    accept(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr.print);

    implicitConstruct(expr.left);
    implicitConstruct(expr.right);

    debug(Semantic) log("=>", expr.print);

    if (pipeDepth > 0) {
      auto pd = pipeDepth;
      pipeDepth = 0;
      Expr r = expr.right;
      accept(expr);
      Stmt stmt = new ExprStmt(expr);
      splitStatements ~= stmt;
      pipeDepth = pd;
      return r;
    }

    while (true) {
      if (isGenerator(expr.right) && isLValue(expr.right)) {
        expr.exprType = expr.right.exprType;
        expr.right = new MemberExpr(expr.right, context.token(Identifier, "input"));
        accept(expr.right);
      }
      else if (isGenerator(expr.left) && isLValue(expr.left)) {
        expr.left = new MemberExpr(expr.left, context.token(Identifier, "output"));
        accept(expr.left);
      }
      else {
        //debug(Semantic) writefln("%s %s", expr.left.exprType, expr.right.exprType);
        if (!expr.left.hasError && !expr.right.hasError) {

          if (expr.left.exprType == typeType) {
            expr.taint;
            error(expr.left, "expected a value expression");
          }
          if (expr.right.exprType == typeType || !isLValue(expr.right)) {
            expr.taint;
            error(expr.right, "not a valid connection target");
          }

          if (expr.left.exprType != expr.right.exprType && !expr.hasError) {
            error(expr, "cannot connect a " ~ mangled(expr.left.exprType) ~ " to a " ~ mangled(expr.right.exprType) ~ " input");
          }
        }
        if (!expr.exprTypeSet)
           expr.exprType = expr.right.exprType;

        debug(Semantic) log("=>", expr.print);
        return expr;
      }
    }
  }

  override Node visit(BinaryExpr expr) {
    debug(Semantic) log("BinaryExpr");
    debug(Semantic) log("=>", expr.print);
    accept(expr.left);
    debug(Semantic) log("=>", expr.print);
    accept(expr.right);
    debug(Semantic) log("=>", expr.print);

    implicitConstruct(expr.left);
    implicitConstruct(expr.right);
    debug(Semantic) log("=>", expr.print);

    while(true) {
      if (isGenerator(expr.left)) {
        expr.left = new MemberExpr(expr.left, context.token(Identifier, "output"));
        accept(expr.left);
      }
      else if (isGenerator(expr.right)) {
        expr.right = new MemberExpr(expr.right, context.token(Identifier, "output"));
        accept(expr.right);
      }
      else {
        Type targetType = typeMap.get(expr.left.exprType, expr.operator.value, expr.right.exprType);
        if (!targetType) {// || (expr.left.exprType != expr.right.exprType)) {
          if (!expr.left.hasError && !expr.right.hasError)
            error(expr.left, "Operation " ~ mangled(expr.left.exprType) ~ " " ~ expr.operator.value.idup ~ " " ~ mangled(expr.right.exprType) ~ " is not defined.");
          return expr.taint();
        }
        expr.exprType = targetType;
        return expr;
      }
    }
  }


  override Node visit(CallExpr expr) {
    debug(Semantic) log("CallExpr");
    debug(Semantic) log("=>", expr.print);
    accept(expr.expr);
    bool argsHasError = false;
    foreach (ref arg; expr.arguments) {
      accept(arg);
      if (arg.hasError) argsHasError = true;
    }

    debug(Semantic) log("=>", expr.print);

    if (expr.expr.hasError || argsHasError) {
      return expr.taint;
    }

    if (auto type = cast(FunctionType)(expr.expr.exprType)) {
      if (type.parameterTypes.length != expr.arguments.length) {
        error(expr, "Wrong number of arguments");
      }
      outer: while (true) {
        for (int i = 0; i < type.parameterTypes.length; ++i) {
          Type paramType = type.parameterTypes[i];
          Type argType = expr.arguments[i].exprType;
          if (paramType != argType)
          {
            if (isGenerator(expr.arguments[i]))
            {
              expr.arguments[i] = new MemberExpr(expr.arguments[i], context.token(Identifier, "output"));
              accept(expr.arguments[i]);
              continue outer;
            }
            else
              error(expr.arguments[i], "Cannot implicity convert argument of type " ~ mangled(argType) ~ " to " ~ mangled(paramType));
          }
        }
        break;
      }
      expr.exprType = type.returnType;
    }
    // TODO: exprType here does not disntinguish between a Generator and it's instance
    //else if (cast(GeneratorType)expr.expr.exprType || cast(StructType)expr.expr.exprType || expr.expr.exprType == numberType) {
    else if (expr.expr.exprType == typeType) {
      // Call constructor
      if (auto refExpr = cast(RefExpr)expr.expr) {
        expr.exprType = refExpr.decl.declType;
      }
    }
    else {
      if (!expr.expr.hasError)
        error(expr, "Cannot call something with type " ~ mangled(expr.expr.exprType));
      return expr.taint;
    }
    debug(Semantic) log("=>", expr.print);
    return expr;
  }

  override Node visit(AssignExpr expr) {
    //TODO: Type check
    debug(Semantic) log("AssignExpr", expr.print);
    accept(expr.left);
    debug(Semantic) log("=>", expr.print);
    accept(expr.right);
    debug(Semantic) log("=>", expr.print);
    expr.exprType = expr.left.exprType;
    return expr;
  }

  override Node visit(UnaryExpr expr) {
    debug(Semantic) log("UnaryExpr", expr.print);
    accept(expr.operand);
    expr.exprType = expr.operand.exprType;
    debug(Semantic) log("=>", expr.print);
    return expr;
  }

  override Node visit(IdentifierExpr expr) {
    if (expr.hasType) return expr;
    debug(Semantic) log("IdentifierExpr", expr.token.value);

    // Look up identifier in symbol table
    Decl decl = symbolTable.lookup(expr.token.value);
    if (!decl) {
      error(expr, "Undefined identifier " ~ expr.token.value.idup);
      /*
      RefExpr re = new RefExpr(expr.token, new VarDecl(errorType, expr.token));
      accept(re);
      re.exprType = errorType;
      return re;
      */
      return expr.taint;
    } else {
      if (auto fieldDecl = cast(FieldDecl)decl) {
        Expr memberExpr = new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.token);
        accept(memberExpr);
        debug(Semantic) log("=>", memberExpr.print);
        return memberExpr;
      }
      else if (auto macroDecl = cast(MacroDecl)decl) {
        Expr memberExpr = new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.token);
        accept(memberExpr);
        debug(Semantic) log("=>", memberExpr.print);
        return memberExpr;
      }
      else {
        Expr refExpr = new RefExpr(expr.token, decl);
        accept(refExpr);
        debug(Semantic) log("=>", refExpr.print);
        return refExpr;
      }
    }
  }
  override Node visit(TypeExpr expr) {
      debug(Semantic) log("TypeExpr", expr.expr.print);
      accept(expr.expr);


      debug(Semantic) log("=>", expr.expr.print);

      if (auto re = cast(RefExpr)expr.expr) {
        if (expr.expr.exprType == typeType && cast(TypeDecl)re.decl) {
          expr.exprType = typeType;
          expr.decl = cast(TypeDecl)re.decl;
          return expr;
        }
      }

      if (!expr.expr.hasError)
        error(expr, "Expected a type");
      return expr.taint();
  }

  override Node visit(RefExpr expr) {
    //Decl decl = currentScope.lookup(expr.identifier.value);
    Decl decl = expr.decl;
    debug(Semantic) log("RefExpr", expr.identifier.value, decl);
    if (cast(TypeDecl)decl) {
      expr.exprType = typeType;
      debug(Semantic) log("=>", expr.print);
      return expr;
    }
    else if (cast(VarDecl)decl) {
      expr.exprType = decl.declType;
      debug(Semantic) log("=>", expr.print);
      return expr;
    }
    else if (cast(MethodDecl)decl) {
      expr.exprType = decl.declType;
      debug(Semantic) log("=>", expr.print);
      return expr;
    }
    else if (auto aliasDecl = cast(AliasDecl)decl) {
      //debug(Semantic) writefln("RefExpr %s %s %s", expr.identifier.value, decl, aliasDecl.targetExpr);
      debug(Semantic) log("=>", aliasDecl.targetExpr.print);
      return aliasDecl.targetExpr;
    }

    //log("", decl, expr.accept(LineNumber()));
    throw __ICE("");
    //expr.exprType = typeType;//decl.declType;
    return expr;
  }

  override Node visit(MemberExpr expr) {
    debug(Semantic) log("MemberExpr", expr.print);
    if (!expr.expr.hasType)
      accept(expr.expr);
    debug(Semantic) log("=>", expr.print);

    if (expr.expr.hasError) return expr.taint;

    Decl decl;
    if (expr.expr.exprType) {
      decl = expr.expr.exprType.decl;
    }
    if (!decl) {
      if (auto refExpr = cast(RefExpr)(expr.expr)) {
        decl = refExpr.decl;
      }
    }
    if (decl) {
      if (decl.declType.kind == GeneratorType.Kind && !isLValue(expr.expr)) {
        error(expr.expr, "Generators can not be temporaries.");
      }
      if (cast(StructDecl)decl) {
        auto structDecl = cast(StructDecl)decl;
        auto ident = expr.identifier.value;
        auto fieldDecl = structDecl.lookup(ident);

        if (fieldDecl) {
          //fieldDecl.accept(this);
          //debug(Semantic) writefln("field %s", fieldDecl.declType);
          expr.exprType = fieldDecl.declType;


          if (auto macroDecl = cast(MacroDecl)fieldDecl) {
            //this(Expr typeExpr, Token identifier, Expr targetExpr, Decl parentDecl) {
            //log("zzz %s %s", expr.print, macroDecl.expansion.print);

            Scope macroScope = new DeclTable();
            symbolTable.pushScope(macroScope);
            macroScope.define("this", new AliasDecl(context.token(Identifier, "this"), expr.expr));
            Expr expansion = macroDecl.expansion.dup();
            accept(expansion);
            symbolTable.popScope();

            //log("zzz %s %s", expansion.print, macroDecl.expansion.print);
            //symbolTable.popScope();
            debug(Semantic) log("=>", expansion.print);
            return expansion;
          }
          debug(Semantic) log("=>", expr.print);
          //debug(Semantic) writefln("aaaaa %s %s %s", fieldDecl, expr.identifier.value, expr.exprType);
          return expr;
        }
        error(expr.expr, "No field " ~ ident.idup ~ " in " ~ structDecl.name.value.idup);
        return expr.taint;
      }
    }

    error(expr.expr, "Cannot access members of " ~ mangled(expr.expr.exprType));
    return expr.taint;
    //assert(0);

    //expr.exprType = expr.expr.exprType;
  }

  override Node visit(ScopeStmt stmt) {
    symbolTable.pushScope(new DeclTable);
    accept(stmt.stmts);
    //currentScope.print();
    symbolTable.popScope();
    return stmt;
  }

  override Node visit(Stmts stmts) {
    //debug(Semantic) writefln("stmts %d [", stmts.stmts.length);
    foreach(ref stmt ; stmts.stmts) {
      debug(Semantic) log("");
      debug(Semantic) log("Stmt");
      accept(stmt);
    }
    //debug(Semantic) writefln("]");
    return stmts;
  }

  override Node visit(MacroDecl decl) {
    debug (Semantic) log("MacroDecl");
    accept(decl.typeExpr);

    //fixme
    //DeclTable aliasScope = new DeclTable();

    /*VarDecl thisVar = new VarDecl(new RefExpr(token(Identifier, "this"), decl.parentDecl), token(Identifier, "this"));
    thisVar.accept(this);
    aliasScope.define("this", thisVar);
    symbolTable.pushScope(aliasScope);
    accept(decl.targetExpr);
    symbolTable.popScope();*/

    //if (auto typeExpr = cast(RefExpr)decl.typeExpr) {
      //if (auto typeDecl = cast(TypeDecl)typeExpr.decl) {

        //decl.declType = typeDecl.declType;
  /*      if (decl.declType != decl.targetExpr.exprType) {
          error(decl.targetExpr, "Expected alias expression to be of type " ~ mangled(decl.declType) ~ " not of type " ~ mangled(decl.targetExpr.exprType) ~ ".");
          decl.targetExpr.exprType = errorType;
        }*/
        //return decl;
    //  }
    //}

    //decl.declType = errorType;
    //error(decl.typeExpr, "Expected type");
    return decl;
  }

  override Node visit(FieldDecl decl) {
    debug(Semantic) log("FieldDecl");
    accept(decl.typeExpr);
    if (decl.valueExpr)
      accept(decl.valueExpr);

    if (decl.typeExpr.exprType == typeType) {
      if (auto typeDecl = decl.typeExpr.decl) {
        decl.declType = typeDecl.declType;
        if (decl.valueExpr && decl.declType != decl.valueExpr.exprType && !decl.valueExpr.hasError) {
          error(decl.valueExpr, "Expected default value to be of type " ~ mangled(decl.declType) ~ " not of type " ~ mangled(decl.valueExpr.exprType) ~ ".");
          decl.valueExpr.taint();
        }
        return decl;
      }
    }
    decl.taint();
    error(decl.typeExpr, "Expected type");
    return decl;
  }

  override Node visit(MethodDecl decl) {
    debug(Semantic) log("MethodDecl");
    if (decl.methodBody) {
      DeclTable funcScope = new DeclTable();
      auto thisToken = context.token(Identifier, "this");
      VarDecl thisVar = new VarDecl(new RefExpr(thisToken, decl.parentDecl), thisToken);
      thisVar.accept(this);
      funcScope.define("this", thisVar);
      symbolTable.pushScope(funcScope);
      accept(decl.methodBody);
      symbolTable.popScope();
    }
    return decl;
  }

  override Node visit(VarDecl decl) {
    debug(Semantic) log("VarDecl", decl.name, decl.typeExpr);
    if (decl.typeExpr) {
      accept(decl.typeExpr);
      if (auto typeExpr = cast(RefExpr)decl.typeExpr) {
        if (auto typeDecl = cast(TypeDecl)typeExpr.decl) {
          decl.declType = typeDecl.declType;
          return decl;
        }
      }
    }
    if (!decl.declType) {
      decl.taint();
      error(decl.typeExpr, "Expected type");
    }
    return decl;
  }

  override Node visit(StructDecl structDecl) {
    debug(Semantic) log("StructDecl", structDecl.name);
    symbolTable.pushScope(structDecl.decls);
    ///FIXME
    foreach(name, ref decl; structDecl.symbolsInDefinitionOrder) {
      if (cast(FieldDecl)decl)accept(decl);
    }
    foreach(name, ref decl; structDecl.symbolsInDefinitionOrder) {
      if (cast(MacroDecl)decl)accept(decl);
    }
    foreach(name, ref decl; structDecl.symbolsInDefinitionOrder)
      if (cast(MethodDecl)decl)accept(decl);
    symbolTable.popScope();
    return structDecl;
  }

  override Node visit(DeclStmt stmt) {
    accept(stmt.expr);
    accept(stmt.decl);

    debug(Semantic) log("DeclStmt", stmt.expr, stmt.decl, mangled(stmt.decl.declType), stmt.identifier.value);

    debug(Semantic) log("Add to symbol table:", stmt.identifier.value, mangled(stmt.decl.declType));
    // Add identifier to symbol table
    if (symbolTable.defines(stmt.identifier.value)) {
      error(stmt.identifier, "Cannot redefine " ~ stmt.identifier.value.idup);
    }
    else {
      symbolTable.define(stmt.identifier.value, stmt.decl);
    }

    return stmt;
  }

  override Node visit(ImportStmt stmt) {
  		import std.path, std.file;
      import duck.compiler;

      debug(Semantic) log("Import", stmt.identifier.value);
      
  		auto p = buildNormalizedPath(sourcePath, "..", stmt.identifier[1..$-1].idup ~ ".duck");
  		if (!p.exists) {
  			context.error(stmt.identifier.span, "Cannot find library at '%s'", p);
  		} else {
  	    auto AST = SourceBuffer(new FileBuffer(p)).parse();
  	    if (auto program = cast(Program)AST.program) {
  	      foreach(Decl decl; program.decls) {
            symbolTable.define(decl.name, decl);
          }
  	    }
  		}
      return new Stmts([]);
  }

  override Node visit(Program program) {
    debug(Semantic) log("Program");
    symbolTable.pushScope(program.imported);
    symbolTable.pushScope(new DeclTable());
    globalScope = symbolTable.scopes[1];

    __gshared static auto freq = new StructType("frequency");
    __gshared static auto dur = new StructType("Duration");
    __gshared static auto Time = new StructType("Time");


    //globalScope.define("Time", new NamedType("Time", new StructType()));
    globalScope.define("SAMPLE_RATE", new VarDecl(freq, context.token(Identifier, "SAMPLE_RATE")));
    globalScope.define("now", new VarDecl(Time, context.token(Identifier, "now")));
    globalScope.define("Duration", new TypeDecl(dur, context.token(Identifier, "Duration")));
    globalScope.define("mono", new TypeDecl(numberType, context.token(Identifier, "mono")));
    globalScope.define("float", new TypeDecl(numberType, context.token(Identifier, "float")));
    globalScope.define("frequency", new TypeDecl(freq, context.token(Identifier, "frequency")));
    globalScope.define("Time", new TypeDecl(Time, context.token(Identifier, "Time")));
    //globalScope.define("Float", new TypeDecl(new NamedType("Float", new StructType())));

    globalScope.define("sin", new VarDecl(new FunctionType(numberType, [numberType]), context.token(Identifier, "sin")));
    globalScope.define("abs", new VarDecl(new FunctionType(numberType, [numberType]), context.token(Identifier, "abs")));
    globalScope.define("hz", new VarDecl(new FunctionType(freq, [numberType]), context.token(Identifier, "hz")));
    globalScope.define("bpm", new VarDecl(new FunctionType(freq, [numberType]), context.token(Identifier, "bpm")));
    globalScope.define("ms", new VarDecl(new FunctionType(dur, [numberType]), context.token(Identifier, "ms")));
    globalScope.define("seconds", new VarDecl(new FunctionType(dur, [numberType]), context.token(Identifier, "seconds")));
    globalScope.define("samples", new VarDecl(new FunctionType(dur, [numberType]), context.token(Identifier, "samples")));

    init();

    foreach(ref decl; program.decls) {
      if (globalScope.defines(decl.name)) {
        error(decl.name, "Cannot redefine " ~ decl.name.idup);
      }
      else {
        globalScope.define(decl.name, decl);
      }
    }

    foreach(ref decl; program.decls) {
      accept(decl);
    }


    //currentScope.print();


    foreach (ref node ; program.nodes)
      accept(node);
    symbolTable.popScope();
    symbolTable.popScope();
    debug(Semantic) log("Done");
    return program;
  }
}

debug auto print(Expr e) {
  return e.accept(ExprToString());
}
