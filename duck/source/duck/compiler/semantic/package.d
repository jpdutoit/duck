module duck.compiler.semantic;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;//, duck.compiler.transforms;
import duck.compiler.visitors, duck.compiler.context;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.semantic.helpers;

import std.stdio;

//debug = Semantic;

struct OperatorTypeMap
{
  alias TypeType = Type[Type];
  alias TypeTypeType = TypeType[Type];
  TypeTypeType[string] binary;

  void set(Type a, string op, Type b, Type c) {
    binary[op][a][b]=c;
  }
  Type get(Type a, string op, Type b) {
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

struct SemanticAnalysis {
  void accept(Target)(ref Target target) {
    logIndent();
    auto obj = target.accept(this);
    logOutdent();

    if (!cast(Target)obj)
     throw __ICE("expected " ~ typeof(this).stringof ~ ".visit(" ~ Target.stringof ~ ") to return a " ~ Target.stringof);
    target = cast(Target)obj;
    //return obj;
  }

  OperatorTypeMap typeMap;

  SymbolTable symbolTable;
  Scope globalScope;
  string sourcePath;

  Context context;


  this(Context context, string sourcePath) {
    this.symbolTable = new SymbolTable();
    this.context = context;
    this.sourcePath = sourcePath;
  }

  Stmt[] splitStatements;
  int pipeDepth = 0;

  void error(Expr expr, string message) {
    context.error(expr.accept(LineNumber()), message);
  }

  void error(Token token, string message) {
    context.error(token, message);
  }

  Type type(string t) {
    Decl decl = symbolTable.lookup(t);
    return decl.declType;
  }

  Expr makeModule(Type type, Expr ctor) {
    auto t = context.temporary();
    return new InlineDeclExpr(t, new VarDeclStmt(t, new VarDecl(type, t), ctor));
  }

  void implicitConstruct(ref Expr expr) {
    //writefln("implicitConstruct %s", expr.accept(ExprToString()));
    // Rewrite: Module
    // to:      Module tmpVar = Module();
    if (expr.exprType == TypeType) {
      if (auto refExpr = cast(RefExpr)expr) {
        if (refExpr.decl.declType.kind == ModuleType.Kind) {
          auto ctor = new CallExpr(refExpr, new TupleExpr([]));
          expr = makeModule(refExpr.decl.declType, ctor);
          accept(expr);
          return;
        }
      }
    }
    // Rewrite: Expr that returns a Module
    // to:      Module tmpVar = expr;
    if (expr.exprType.isKindOf!ModuleType && !isLValue(expr)) {
      expr = makeModule(expr.exprType, expr);
      accept(expr);
    }
  }



  Node visit(ErrorExpr expr) {
    return expr;
  }

  Node visit(InlineDeclExpr expr) {
    debug(Semantic) log("InlineDeclExpr", expr);
    accept(expr.declStmt);

    splitStatements ~= expr.declStmt;
    //debug(Semantic) writefln("InlineDeclExpr2 %s", expr.declStmt);
    Expr ident = new IdentifierExpr(expr.token);
    accept(ident);
    debug(Semantic) log("=>", ident);
    //debug(Semantic) writefln("InlineDeclExpr3 %s", ident);

    return ident;
  }

  Node visit(ExprStmt stmt) {
    debug(Semantic) log("ExprStmt", stmt.expr);
    if (auto declExpr = cast(InlineDeclExpr) stmt.expr) {
      accept(declExpr.declStmt);
      return declExpr.declStmt;
    }

    splitStatements = [];
    accept(stmt.expr);
    debug(Semantic) log("=>", stmt.expr);
    if (splitStatements.length > 0) {
      return new Stmts(splitStatements ~ stmt);
    }
    return stmt;
  }

  Node visit(ArrayLiteralExpr expr) {
    debug(Semantic) log("ArrayLiteralExpr", expr);
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
    debug(Semantic) log("=>", expr);
    return expr;
  }

  Node visit(PipeExpr expr) {
    debug(Semantic) log("PipeExpr");
    debug(Semantic) log("=>", expr);
    pipeDepth++;
    accept(expr.left);
    debug(Semantic) log("=>", expr);
    accept(expr.right);
    pipeDepth--;
    debug(Semantic) log("=>", expr);

    implicitConstruct(expr.left);
    implicitConstruct(expr.right);

    debug(Semantic) log("=>", expr);

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
      if (isModule(expr.right) && isLValue(expr.right)) {
        expr.exprType = expr.right.exprType;
        expr.right = new MemberExpr(expr.right, context.token(Identifier, "input"));
        accept(expr.right);
      }
      else if (isModule(expr.left) && isLValue(expr.left)) {
        expr.left = new MemberExpr(expr.left, context.token(Identifier, "output"));
        accept(expr.left);
      }
      else {
        if (!expr.left.hasError && !expr.right.hasError) {
          if (expr.left.exprType == TypeType) {
            expr.taint;
            error(expr.left, "expected a value expression");
          }
          if (expr.right.exprType == TypeType || !isLValue(expr.right)) {
            expr.taint;
            error(expr.right, "not a valid connection target");
          }
          if (expr.left.exprType != expr.right.exprType && !expr.hasError) {
            error(expr, "cannot connect a " ~ mangled(expr.left.exprType) ~ " to a " ~ mangled(expr.right.exprType) ~ " input");
          }
        }
        if (!expr.exprTypeSet)
           expr.exprType = expr.right.exprType;

        debug(Semantic) log("=>", expr);
        return expr;
      }
    }
  }

  Node visit(BinaryExpr expr) {
    debug(Semantic) log("BinaryExpr");
    debug(Semantic) log("=>", expr);
    accept(expr.left);
    debug(Semantic) log("=>", expr);
    accept(expr.right);
    debug(Semantic) log("=>", expr);

    implicitConstruct(expr.left);
    implicitConstruct(expr.right);
    debug(Semantic) log("=>", expr);

    while(true) {
      if (isModule(expr.left)) {
        expr.left = new MemberExpr(expr.left, context.token(Identifier, "output"));
        accept(expr.left);
      }
      else if (isModule(expr.right)) {
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


  Node visit (TupleExpr expr) {
    debug(Semantic) log("TupleExpr", expr);
    bool tupleError = false;
    Type[] elementTypes = [];
    assumeSafeAppend(elementTypes);
    foreach (ref Expr e; expr) {
      accept(e);
      elementTypes ~= e.exprType;
      if (e.hasError)
        tupleError = true;
      else
        implicitConstruct(e);
    }
    debug(Semantic) log("=>", expr);
    if (tupleError) return expr.taint;

    expr.exprType = new TupleType(elementTypes);
    debug(Semantic) log("=>", expr);
    return expr;
  }

  Node visit(CallExpr expr) {
    debug(Semantic) log("CallExpr");
    debug(Semantic) log("=>", expr);
    accept(expr.expr);
    accept(expr.arguments);
    debug(Semantic) log("=>", expr);

    if (expr.expr.hasError || expr.arguments.hasError) {
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
            if (isModule(expr.arguments[i]))
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
    else if (expr.expr.exprType == TypeType) {
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
    debug(Semantic) log("=>", expr);
    return expr;
  }

  Node visit(AssignExpr expr) {
    //TODO: Type check
    debug(Semantic) log("AssignExpr", expr);
    accept(expr.left);
    debug(Semantic) log("=>", expr);
    accept(expr.right);
    debug(Semantic) log("=>", expr);
    expr.exprType = expr.left.exprType;
    return expr;
  }

  Node visit(UnaryExpr expr) {
    debug(Semantic) log("UnaryExpr", expr);
    accept(expr.operand);
    expr.exprType = expr.operand.exprType;
    debug(Semantic) log("=>", expr);
    return expr;
  }

  Node visit(IdentifierExpr expr) {
    if (expr.hasType) return expr;
    debug(Semantic) log("IdentifierExpr", expr.token.value);

    // Look up identifier in symbol table
    Decl decl = symbolTable.lookup(expr.token.value);
    if (!decl) {
      error(expr, "Undefined identifier " ~ expr.token.value.idup);
      /*
      RefExpr re = new RefExpr(expr.token, new VarDecl(ErrorType, expr.token));
      accept(re);
      re.exprType = ErrorType;
      return re;
      */
      return expr.taint;
    } else {
      if (auto fieldDecl = cast(FieldDecl)decl) {
        Expr memberExpr = new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.token);
        accept(memberExpr);
        debug(Semantic) log("=>", memberExpr);
        return memberExpr;
      }
      else if (auto macroDecl = cast(MacroDecl)decl) {
        Expr memberExpr = new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.token);
        accept(memberExpr);
        debug(Semantic) log("=>", memberExpr);
        return memberExpr;
      }
      else {
        Expr refExpr = new RefExpr(expr.token, decl);
        accept(refExpr);
        debug(Semantic) log("=>", refExpr);
        return refExpr;
      }
    }
  }
  Node visit(TypeExpr expr) {
      debug(Semantic) log("TypeExpr", expr.expr);
      accept(expr.expr);


      debug(Semantic) log("=>", expr.expr);

      if (auto re = cast(RefExpr)expr.expr) {
        if (expr.expr.exprType == TypeType && cast(TypeDecl)re.decl) {
          expr.exprType = TypeType;
          expr.decl = cast(TypeDecl)re.decl;
          return expr;
        }
      }

      if (!expr.expr.hasError)
        error(expr, "Expected a type");
      return expr.taint();
  }

  Node visit(RefExpr expr) {
    //Decl decl = currentScope.lookup(expr.identifier.value);
    Decl decl = expr.decl;
    debug(Semantic) log("RefExpr", expr.identifier.value, decl);

    auto retExpr = decl.visit!(
      (TypeDecl decl) => (expr.exprType = TypeType, expr),
      (VarDecl decl) => (expr.exprType = decl.declType, expr),
      (MethodDecl decl) => (expr.exprType = decl.declType, expr),
      (AliasDecl decl) => decl.targetExpr
    );
    debug(Semantic) log("=>", retExpr);
    return retExpr;
  }

  Node visit(MemberExpr expr) {
    debug(Semantic) log("MemberExpr", expr);
    if (!expr.left.hasType)
      accept(expr.left);
    debug(Semantic) log("=>", expr);
    implicitConstruct(expr.left);
    debug(Semantic) log("=>", expr);

    if (expr.left.hasError) return expr.taint;

    if (auto ge = cast(ModuleType)expr.left.exprType) {
      StructDecl decl = ge.decl;
      if (!isLValue(expr.left)) {
        __ICE("Modules can not be temporaries.");
      }
      auto structDecl = cast(StructDecl)decl;
      //auto ident = expr.identifier.value;
      auto ident = expr.right.visit!((IdentifierExpr e) => e.token.value);
      auto fieldDecl = structDecl.lookup(ident);

      if (fieldDecl) {
        expr.exprType = fieldDecl.declType;

        if (auto macroDecl = cast(MacroDecl)fieldDecl) {
          Scope macroScope = new DeclTable();
          symbolTable.pushScope(macroScope);
          macroScope.define("this", new AliasDecl(context.token(Identifier, "this"), expr.left));
          Expr expansion = macroDecl.expansion.dup();
          accept(expansion);
          symbolTable.popScope();

          debug(Semantic) log("=>", expansion);
          return expansion;
        }
        debug(Semantic) log("=>", expr);
        return expr;
      }
      error(expr, "No field " ~ ident.idup ~ " in " ~ structDecl.name.value.idup);
      return expr.taint;
    }

    error(expr.left, "Cannot access members of " ~ mangled(expr.left.exprType));
    return expr.taint;
  }

  Node visit(ScopeStmt stmt) {
    symbolTable.pushScope(new DeclTable);
    accept(stmt.stmts);
    symbolTable.popScope();
    return stmt;
  }

  Node visit(Stmts stmts) {
    foreach(ref stmt ; stmts.stmts) {
      debug(Semantic) log("");
      debug(Semantic) log("Stmt");
      accept(stmt);
    }
    return stmts;
  }

  Node visit(MacroDecl decl) {
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
          decl.targetExpr.exprType = ErrorType;
        }*/
        //return decl;
    //  }
    //}

    //decl.declType = ErrorType;
    //error(decl.typeExpr, "Expected type");
    return decl;
  }

  Node visit(FieldDecl decl) {
    debug(Semantic) log("FieldDecl");
    accept(decl.typeExpr);
    if (decl.valueExpr)
      accept(decl.valueExpr);

    if (decl.typeExpr.exprType == TypeType) {
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

  Node visit(MethodDecl decl) {
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

  Node visit(VarDecl decl) {
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

  Node visit(StructDecl structDecl) {
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

  Node visit(VarDeclStmt stmt) {
    debug(Semantic) log("VarDeclStmt", stmt.expr);
    accept(stmt.expr);
    debug(Semantic) log("=>", stmt.expr);
    accept(stmt.decl);
    debug(Semantic) log("=>", stmt.decl);

    debug(Semantic) log("VarDeclStmt", stmt.expr, stmt.decl);//, mangled(stmt.decl.declType), stmt.identifier.value);
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


  Node visit(TypeDeclStmt stmt) {
    if (globalScope.defines(stmt.decl.name)) {
      error(stmt.decl.name, "Cannot redefine " ~ stmt.decl.name.idup);
    }
    else {
      globalScope.define(stmt.decl.name, stmt.decl);
    }
    accept(stmt.decl);
    if (stmt.decl.declType != ErrorType) {
      library.exports ~= stmt.decl;
    }
    return stmt;
  }

  Node visit(ImportStmt stmt) {
    import std.path, std.file, duck.compiler;

    debug(Semantic) log("Import", stmt.identifier.value);

    auto p = buildNormalizedPath(sourcePath, "..", stmt.identifier[1..$-1].idup ~ ".duck");
    if (!p.exists) {
      context.error(stmt.identifier, "Cannot find library at '%s'", p);
    } else {
      auto AST = SourceBuffer(new FileBuffer(p)).parse();
      if (auto library = cast(Library)AST.library) {
        foreach(decl; library.exports) {
          this.library.imports.define(decl.name, decl);
        }
      }

    }
    //return stmt;
    return new Stmts([]);
  }

  Library library;

  Node visit(Library library) {
    this.library = library;
    debug(Semantic) log("Library");

    symbolTable.pushScope(library.imports);
    symbolTable.pushScope(new DeclTable());
    globalScope = symbolTable.scopes[1];

    __gshared static auto freq = new StructType("frequency");
    __gshared static auto dur = new StructType("duration");
    __gshared static auto Time = new StructType("Time");


    // TODO: These should loaded from extern definitions in the standard library.

    globalScope.define("SAMPLE_RATE", new VarDecl(freq, context.token(Identifier, "SAMPLE_RATE")));
    globalScope.define("now", new VarDecl(Time, context.token(Identifier, "now")));
    globalScope.define("duration", new TypeDecl(dur, context.token(Identifier, "duration")));
    globalScope.define("mono", new TypeDecl(NumberType, context.token(Identifier, "mono")));
    globalScope.define("float", new TypeDecl(NumberType, context.token(Identifier, "float")));
    globalScope.define("frequency", new TypeDecl(freq, context.token(Identifier, "frequency")));
    globalScope.define("Time", new TypeDecl(Time, context.token(Identifier, "Time")));


    globalScope.define("sin", new VarDecl(new FunctionType(NumberType, [NumberType]), context.token(Identifier, "sin")));
    globalScope.define("abs", new VarDecl(new FunctionType(NumberType, [NumberType]), context.token(Identifier, "abs")));
    globalScope.define("hz", new VarDecl(new FunctionType(freq, [NumberType]), context.token(Identifier, "hz")));
    globalScope.define("bpm", new VarDecl(new FunctionType(freq, [NumberType]), context.token(Identifier, "bpm")));
    globalScope.define("ms", new VarDecl(new FunctionType(dur, [NumberType]), context.token(Identifier, "ms")));
    globalScope.define("seconds", new VarDecl(new FunctionType(dur, [NumberType]), context.token(Identifier, "seconds")));
    globalScope.define("samples", new VarDecl(new FunctionType(dur, [NumberType]), context.token(Identifier, "samples")));

    typeMap.set(NumberType, "*", NumberType, NumberType);
    typeMap.set(NumberType, "+", NumberType, NumberType);
    typeMap.set(NumberType, "-", NumberType, NumberType);
    typeMap.set(NumberType, "/", NumberType, NumberType);
    typeMap.set(NumberType, "%", NumberType, NumberType);

    typeMap.set(type("Time"), "%", type("duration"), type("duration"));
    typeMap.set(NumberType, "*", type("duration"), type("duration"));
    typeMap.set(type("duration"), "+", type("duration"), type("duration"));
    typeMap.set(type("duration"), "-", type("duration"), type("duration"));

    typeMap.set(type("duration"), "*", NumberType, type("duration"));
    typeMap.set(type("frequency"), "*", NumberType, type("frequency"));
    typeMap.set(type("frequency"), "/", NumberType, type("frequency"));
    typeMap.set(type("frequency"), "/", type("frequency"), NumberType);
    typeMap.set(type("frequency"), "+", type("frequency"), type("frequency"));
    typeMap.set(type("frequency"), "-", type("frequency"), type("frequency"));
    typeMap.set(NumberType, "*", type("frequency"), type("frequency"));

    foreach (ref node ; library.nodes)
      accept(node);
    symbolTable.popScope();
    symbolTable.popScope();
    debug(Semantic) log("Done");
    return library;
  }


  // Nothing to do for these
  Node visit(LiteralExpr expr) {
    return expr;
  }
}
