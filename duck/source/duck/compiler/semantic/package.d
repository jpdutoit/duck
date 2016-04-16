module duck.compiler.semantic;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;//, duck.compiler.transforms;
import duck.compiler.visitors, duck.compiler.context;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.semantic.helpers;

import std.stdio;
///debug = Semantic;

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
    debug(Semantic) logIndent();
    auto obj = target.accept(this);
    debug(Semantic) logOutdent();

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

  void implicitCall(ref Expr expr) {
    expr.exprType.visit!(
      delegate(OverloadSetType os) {
        expr = new CallExpr(expr, new TupleExpr([]));
        accept(expr);
      },
      (Type type) { }
    );
  }
  void implicitConstruct(ref Expr expr) {
    expr.exprType.visit!(
      delegate(TypeType t) {
        // Rewrite: ModuleType
        // to:      ModuleType tmpVar = Module();
        if (auto refExpr = cast(RefExpr)expr) {
          if (refExpr.decl.declType.isKindOf!ModuleType) {
            auto ctor = new CallExpr(refExpr, new TupleExpr([]));
            expr = makeModule(refExpr.decl.declType, ctor);
            accept(expr);
            return;
          }
        }
      },
      delegate(ModuleType t) {
        // Rewrite: Expr that returns a ModuleType temporary
        // to:      ModuleType tmpVar = expr;
        if (!expr.isLValue) {
          expr = makeModule(expr.exprType, expr);
          accept(expr);
        }
      },
      delegate(Type type) {}
    );
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
    expr.exprType = ArrayType.create(expr.exprs[0].exprType);
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
    implicitCall(expr.left);
    implicitConstruct(expr.right);
    implicitCall(expr.right);

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
          if (expr.left.exprType.kind == TypeType.Kind) {
            expr.taint;
            error(expr.left, "expected a value expression");
          }
          if (expr.right.exprType.kind == TypeType.Kind || !isLValue(expr.right)) {
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
    implicitCall(expr.left);
    implicitConstruct(expr.right);
    implicitCall(expr.right);
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
        auto os = cast(OverloadSet)symbolTable.lookup(expr.operator.value);
        if (os) {
          TupleExpr args = new TupleExpr([expr.left, expr.right]);
          accept(args);
          CallableDecl[] viable;
          auto best = findBestOverload(os, args, &viable);

          if (best) {
            if (!best.external) {
              Expr e = new CallExpr(new RefExpr(expr.operator, best), args);
              accept(e);
              debug(Semantic) log("=>", e);
              return e;
            }
            expr.exprType = best.getResultType();
            debug(Semantic) log("=>", expr);
            return expr;
          }


        }


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
      if (e.hasError)
        tupleError = true;
      else {
        implicitConstruct(e);
        implicitCall(e);
      }
      elementTypes ~= e.exprType;
    }
    debug(Semantic) log("=>", expr);
    if (tupleError) return expr.taint;

    expr.exprType = TupleType.create(elementTypes);
    debug(Semantic) log("=>", expr);
    return expr;
  }


  CallableDecl findBestOverload(OverloadSet os, TupleExpr args, CallableDecl[]* viable) {
    int bestScore = 0;
    int matches = 0;
    CallableDecl bestCallable;

    CallableDecl[32] overloads;
    foreach(decl; os.decls) {
      //FunctionType type = cast(FunctionType)decl.declType;
      debug(Semantic) log("Checking", decl, args.exprType,  ((cast(TupleType)args.exprType).elementTypes));
      int score = ((cast(TupleType)args.exprType).elementTypes).matchScore(decl);
      debug(Semantic) log("=> check", args.exprType.describe, decl);
      if (score >= bestScore) {
        if (score != bestScore) {
          matches = 0;
        }
        overloads[matches++] = decl;
        bestScore = score;
        bestCallable = decl;
        debug(Semantic) log("=>", bestScore, bestCallable);
      }
    }
    if (matches > 1) {
      foreach (overload; overloads) *viable ~= overload;
      //overloads[0..matches].copy(*viable);
      return null;
    }
    if (bestCallable !is null && bestScore >= 0) {
      return bestCallable;
    }
    return null;
  }


  Expr findTarget(Expr expr) {
    return expr.visit!(
      (Expr expr) => cast(Expr)null,
      (MemberExpr expr) => expr.left);
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

    return expr.expr.exprType.visit!(
      delegate (OverloadSetType ot) {
        OverloadSet os = ot.overloadSet;
        CallableDecl[] viable;
        CallableDecl best = findBestOverload(os, expr.arguments, &viable);

        if (viable.length > 0) {
          error(expr, "Ambigious call.");
          expr.taint;
          return expr;
        }
        else if (best) {
          expr.exprType = (cast(FunctionType)best.declType).returnType;
          debug(Semantic) log("=>", expr);
          return expr;
        }
        else {
          error(expr, "No functions matches arguments.");
          expr.taint();
          return expr;
        }
      },
      /*delegate (FunctionType ft)  {
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
      },*/
      /*delegate (FunctionType type) {
        import std.algorithm.comparison;
        ulong len = min(type.parameters.length, expr.arguments.length);
        if (type.parameters.length != expr.arguments.length) {
          error(expr, "Wrong number of arguments");
          expr.taint();
        }
        outer: while (true) {
          for (int i = 0; i < len; ++i) {
            Type paramType = type.parameters[i];
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
        return expr;
      },*/
      delegate (TypeType tt) {
        // Call constructor
        if (auto refExpr = cast(RefExpr)expr.expr) {
          expr.exprType = refExpr.decl.declType;
        }
        return expr;
      },
      delegate (Type tt) {
        if (!expr.expr.hasError)
          error(expr, "Cannot call something with type " ~ mangled(expr.expr.exprType));
        return expr.taint;
      }
    );
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
    debug(Semantic) log("IdentifierExpr", expr.identifier);

    // Look up identifier in symbol table
    Decl decl = symbolTable.lookup(expr.identifier);
    if (!decl) {
      error(expr, "Undefined identifier " ~ expr.identifier.idup);
      //return new ErrorExpr(expr.accept(LineNumber()));
      return expr.taint;
    } else {

      Expr resolve(Decl decl) {
        return decl.visit!(
          (OverloadSet overloadSet) {
            // TODO: This is a hack!!
            if (overloadSet.decls.length == 1 && cast(MacroDecl)overloadSet.decls[0]) {
              return resolve(overloadSet.decls[0]);
            }
            return new RefExpr(expr.token, overloadSet);
          },
          (MethodDecl methodDecl)
            => new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.dupl()),
          (FieldDecl fieldDecl)
            => new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.dupl()),
          (MacroDecl macroDecl)
            => new MemberExpr(new IdentifierExpr(context.token(Identifier, "this")), expr.dupl()),
          (Decl decl) => new RefExpr(expr.token, decl)
        );
      }

      auto result = resolve(decl);

      accept(result);
      debug(Semantic) log("=>", result);
      return result;
    }
  }

  Node visit(TypeExpr expr) {
      debug(Semantic) log("TypeExpr", expr.expr);
      accept(expr.expr);
      debug(Semantic) log("=>", expr.expr);

      if (auto re = cast(RefExpr)expr.expr) {
        if (expr.expr.exprType.isKindOf!TypeType && cast(TypeDecl)re.decl) {
          expr.exprType = TypeType.create;
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
      (TypeDecl decl) => (expr.exprType = TypeType.create, expr),
      (VarDecl decl) => (expr.exprType = decl.declType, expr),
      (MethodDecl decl) => (expr.exprType = decl.declType, expr),
      (FunctionDecl decl) => (expr.exprType = decl.declType, expr),
      (OverloadSet os) => (expr.exprType = OverloadSetType.create(os), expr),
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
    implicitCall(expr.left);
    debug(Semantic) log("=>", expr);

    if (expr.left.hasError) return expr.taint;

    if (auto ge = cast(ModuleType)expr.left.exprType) {
      StructDecl decl = ge.decl;
      if (!isLValue(expr.left)) {
        __ICE("Modules can not be temporaries.");
      }
      auto structDecl = cast(StructDecl)decl;
      //auto ident = expr.identifier.value;
      auto ident = expr.right.visit!((IdentifierExpr e) => e.identifier);
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
    accept(decl.returnType);
    Type[] paramTypes;
    for (int i = 0; i < decl.parameterTypes.length; ++i) {
      accept(decl.parameterTypes[i]);
      paramTypes ~= decl.parameterTypes[i].decl.declType;
    }
    debug(Semantic) log("=>", decl.parameterTypes, "->", decl.returnType);
    auto type = FunctionType.create(decl.returnType.decl.declType, TupleType.create(paramTypes));
    type.decl = decl;
    decl.declType = type;
    debug(Semantic) log("=>", decl.declType.describe);
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

  FunctionDecl visit(FunctionDecl decl) {
    debug(Semantic) log("FunctionDecl", decl.name, decl.parameterTypes, "->", decl.returnType);
    accept(decl.returnType);
    Type[] paramTypes;
    for (int i = 0; i < decl.parameterTypes.length; ++i) {
      accept(decl.parameterTypes[i]);
      paramTypes ~= decl.parameterTypes[i].decl.declType;
    }
    debug(Semantic) log("=>", decl.parameterTypes, "->", decl.returnType);
    auto type = FunctionType.create(decl.returnType.decl.declType, TupleType.create(paramTypes));
    type.decl = decl;
    decl.declType = type;

    debug(Semantic) log("=>", decl.declType.describe);
    return decl;
  }

  Node visit(FieldDecl decl) {
    debug(Semantic) log("FieldDecl");
    accept(decl.typeExpr);
    if (decl.valueExpr)
      accept(decl.valueExpr);

    if (decl.typeExpr.exprType.kind == TypeType.Kind) {
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
    if (!cast(CallableDecl)stmt.decl && globalScope.defines(stmt.decl.name)) {
      error(stmt.decl.name, "Cannot redefine " ~ stmt.decl.name.idup);
    }
    else {
      globalScope.define(stmt.decl.name, stmt.decl);
    }
    accept(stmt.decl);
    if (stmt.decl.declType.kind != ErrorType.Kind) {
      library.exports ~= stmt.decl;
    }
    return stmt;
  }

  Node visit(ImportStmt stmt) {
    import std.path, std.file, duck.compiler;

    debug(Semantic) log("Import", stmt.identifier.value);

    if (stmt.identifier.length <= 2) {
      context.error(stmt.identifier, "Expected path to package to not be empty.");
      return new Stmts([]);
    }
    string[] paths;
    if (stmt.identifier[1] == '.' || stmt.identifier[1] == '/') {
      paths ~= buildNormalizedPath(sourcePath, "..", stmt.identifier[1..$-1].idup ~ ".duck").idup;  
    }
    else {
      for (int i = 0; i < context.packageRoots.length; ++i) {
        paths ~= buildNormalizedPath(context.packageRoots[i], "duck_packages", stmt.identifier[1..$-1].idup ~ ".duck").idup;
      }
    }
    for (int i = 0; i < paths.length; ++i) {
      auto path = paths[i];
      if (path.exists()) {
        auto AST = SourceBuffer(new FileBuffer(path)).parse();
        if (auto library = cast(Library)AST.library) {
          foreach(decl; library.exports) {
            this.library.imports.define(decl.name, decl);
          }
        }
        return new Stmts([]);
      }
    }
    context.error(stmt.identifier, "Cannot find library at '%s'", paths[$-1]);
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

    __gshared static auto freq = StructType.create("frequency");
    __gshared static auto dur = StructType.create("duration");
    __gshared static auto Time = StructType.create("Time");


    // TODO: These should loaded from extern definitions in the standard library.

    globalScope.define("SAMPLE_RATE", new VarDecl(freq, context.token(Identifier, "SAMPLE_RATE")));
    globalScope.define("now", new VarDecl(Time, context.token(Identifier, "now")));
    globalScope.define("duration", new TypeDecl(dur, context.token(Identifier, "duration")));
    globalScope.define("mono", new TypeDecl(NumberType.create, context.token(Identifier, "mono")));
    globalScope.define("float", new TypeDecl(NumberType.create, context.token(Identifier, "float")));
    globalScope.define("frequency", new TypeDecl(freq, context.token(Identifier, "frequency")));
    globalScope.define("Time", new TypeDecl(Time, context.token(Identifier, "Time")));

    typeMap.set(NumberType.create, "*", NumberType.create, NumberType.create);
    //typeMap.set(NumberType.create, "+", NumberType.create, NumberType.create);
    typeMap.set(NumberType.create, "-", NumberType.create, NumberType.create);
    typeMap.set(NumberType.create, "/", NumberType.create, NumberType.create);
    typeMap.set(NumberType.create, "%", NumberType.create, NumberType.create);

    typeMap.set(type("Time"), "%", type("duration"), type("duration"));
    typeMap.set(NumberType.create, "*", type("duration"), type("duration"));
    typeMap.set(type("duration"), "+", type("duration"), type("duration"));
    typeMap.set(type("duration"), "-", type("duration"), type("duration"));

    typeMap.set(type("duration"), "*", NumberType.create, type("duration"));
    typeMap.set(type("frequency"), "*", NumberType.create, type("frequency"));
    typeMap.set(type("frequency"), "/", NumberType.create, type("frequency"));
    typeMap.set(type("frequency"), "/", type("frequency"), NumberType.create);
    typeMap.set(type("frequency"), "+", type("frequency"), type("frequency"));
    typeMap.set(type("frequency"), "-", type("frequency"), type("frequency"));
    typeMap.set(NumberType.create, "*", type("frequency"), type("frequency"));

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
