module duck.compiler.semantic;

import duck.compiler.ast, duck.compiler.token, duck.compiler.types, duck.compiler.transforms;
import duck.compiler.visitors;

alias String = const(char)[];


Token token(Token.Type type, String s) {
  return Token(type, s, 0, cast(int)(s.length));
}

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


interface Scope {
  Decl lookup(String identifier);
  void define(String identifier, Decl decl);
}

class DeclTable : Scope {
  Decl[String] symbols;

  void define(String identifier, Decl decl) {
    if (identifier in symbols) {
      throw new Error("Cannot redefine " ~ identifier.idup);
    }
    symbols[identifier] = decl;
  }

  Decl lookup(String identifier) {
    if (identifier in symbols) {
      return symbols[identifier];
    }
    return null;
  }
}

class SymbolTable {
		Decl[String] symbols;
		SymbolTable parent;

		this(SymbolTable parent) {
			this.parent = parent;
		}

		void define(String identifier, Decl decl) {
      if (identifier in symbols) {
        throw new Error("Cannot redefine " ~ identifier.idup);
      }
			symbols[identifier] = decl;
		}

		Decl lookup(String identifier, bool recurse = true) {
			if (identifier in symbols) {
				return symbols[identifier];
			}
			if (recurse && parent) return parent.lookup(identifier);
			return null;
		}

		void print() {
			foreach (String name, Decl decl; symbols) {
				if (cast(VarDecl)decl) {
					writefln("var %s = %s ", name, mangled(decl.declType));
				} else {
					writefln("type %s = %s %s", name, mangled(decl.declType), decl);
				}
			}
		}
}

class SemanticAnalysis : TransformVisitor {

  OperatorTypeMap typeMap;

	SymbolTable globalScope;
	SymbolTable[] scopes;

  this() {
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
    typeMap.set(type("Duration"), "+", type("Duration"), type("Duration"));
    typeMap.set(type("Duration"), "-", type("Duration"), type("Duration"));

    typeMap.set(type("Duration"), "*", numberType, type("Duration"));
    typeMap.set(type("frequency"), "*", numberType, type("frequency"));
    typeMap.set(numberType, "*", type("frequency"), type("frequency"));
  }

  Type type(string t) {
    Decl decl = currentScope.lookup(t);
    writefln("a %s %s", t, decl);
    while (decl && cast(NamedType)decl.declType) {
      Decl old = decl;
      NamedType namedType = cast(NamedType)(decl.declType);
      decl = currentScope.lookup(namedType.name);
      if (decl is old) break;
    }
    return decl.declType;
  }


	@property
	SymbolTable currentScope() {
		return scopes[$-1];
	}

	void pushScope() {
		SymbolTable symbolTable = new SymbolTable(scopes.length > 0 ? scopes[$-1] : null);
		scopes ~= symbolTable;
	}

	void popScope() {
		scopes = scopes[0..$-1];
	}

  void error(Expr expr, string message) {
    import std.conv : to;
    import duck.compiler.visitors : LineNumber;
    throw new Error("("~ expr.accept(LineNumber()).to!string ~") " ~ message);
  }

	alias visit = TransformVisitor.visit;

	override Node visit(ExprStmt expr) {
		accept(expr.expr);
		return expr;
	}



  override Node visit(PipeExpr expr) {
    accept(expr.left);
		accept(expr.right);
    writefln("pipeExpr %s", expr.accept(ExprToString()));

    while (true) {
      if (isGenerator(expr.right)) {
        expr.exprType = expr.right.exprType;
        expr.right = new MemberExpr(expr.right, token(Identifier, "input"));
    		accept(expr.right);
      }
      else if (isGenerator(expr.left)) {
        expr.left = new MemberExpr(expr.left, token(Identifier, "output"));
    		accept(expr.left);
      }
      else {
        writefln("%s %s", expr.left.exprType, expr.right.exprType);
        if (expr.left.exprType != expr.right.exprType)
          error(expr.right, "Cannot pipe a " ~ mangled(expr.left.exprType) ~ " to a " ~ mangled(expr.right.exprType));
        if (!expr.exprTypeSet)
           expr.exprType = expr.right.exprType;
        return expr;
      }
  }
  }

	override Node visit(BinaryExpr expr) {
		accept(expr.left);
		accept(expr.right);
    writefln("binaryExpr %s", expr.accept(ExprToString()));

    while(true) {
      if (isGenerator(expr.left)) {
        expr.left = new MemberExpr(expr.left, token(Identifier, "output"));
        accept(expr.left);
      }
      else if (isGenerator(expr.right)) {
        expr.right = new MemberExpr(expr.right, token(Identifier, "output"));
        accept(expr.right);
      }
      else {
        Type targetType = typeMap.get(expr.left.exprType, expr.operator.value, expr.right.exprType);
        if (!targetType) {// || (expr.left.exprType != expr.right.exprType)) {
          error(expr.left, "Cannot " ~ expr.operator.value.idup ~ " a " ~ mangled(expr.left.exprType) ~ " and a " ~ mangled(expr.right.exprType));
        }
        expr.exprType = targetType;
        return expr;
      }
    }
	}

  override Node visit(CallExpr expr) {
    accept(expr.expr);
    foreach (ref arg; expr.arguments) {
      accept(arg);
    }
    writefln("callexp %s", expr.accept(ExprToString()));

    if (auto type = cast(FunctionType)(expr.expr.exprType)) {
      if (type.parameterTypes.length != expr.arguments.length) {
        throw new Error("Wrong number of arguments");
      }
      outer: while (true) {
        for (int i = 0; i < type.parameterTypes.length; ++i) {
          Type paramType = type.parameterTypes[i];
          Type argType = expr.arguments[i].exprType;
          if (paramType != argType)
          {
            if (isGenerator(expr.arguments[i]))
            {
              expr.arguments[i] = new MemberExpr(expr.arguments[i], token(Identifier, "output"));
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
      if (auto declExpr = cast(DeclExpr)expr.expr) {
        expr.exprType = declExpr.decl.declType;
      }
    }
    else {
      error(expr, "Cannot call something with type " ~ mangled(expr.expr.exprType));
    }
    return expr;
  }

	override Node visit(AssignExpr expr) {
		accept(expr.left);
		accept(expr.right);
		expr.exprType = expr.left.exprType;
		return expr;
	}

	override Node visit(UnaryExpr expr) {
		accept(expr.operand);
		expr.exprType = expr.operand.exprType;
		return expr;
	}

	override Node visit(IdentifierExpr expr) {
		// Look up identifier in symbol table
		Decl decl = currentScope.lookup(expr.token.value);
		if (!decl) {
			throw new Error("Undefined identifier " ~ expr.token.value.idup);
		} else {

      DeclExpr declExpr = new DeclExpr(expr.token, decl);
      accept(declExpr);
      return declExpr;
    }
		return expr;
	}

  override Node visit(DeclExpr expr) {

    //Decl decl = currentScope.lookup(expr.identifier.value);
    Decl decl = expr.decl;
    writefln("DeclExpr %s %s", expr.identifier.value, decl);
    if (cast(TypeDecl)decl) {
      expr.exprType = typeType;
      return expr;
    }
    else if (cast(VarDecl)decl) {
      expr.exprType = decl.declType;
      return expr;
    }
    /*if (false &&cast(NamedType)(decl.declType)) {

      while (cast(NamedType)(decl.declType)) {
        Decl old = decl;
        NamedType namedType = cast(NamedType)(decl.declType);
        decl = currentScope.lookup(namedType.name);


        //writefln("bbb %s %s", namedType.name, decl);
        if (decl == old) break;
      }
      expr = new DeclExpr(expr.identifier, decl);
    }*/
    writefln("%s", decl);
    throw new Error("e");
    //expr.exprType = typeType;//decl.declType;
    return expr;
  }

  Decl resolve(Type type) {
    if (type.decl) return type.decl;
    Decl decl;
    while (cast(NamedType)(type)) {
      Decl old = decl;
      NamedType namedType = cast(NamedType)(type);
      decl = currentScope.lookup(namedType.name);
      type = decl.declType;
      if (decl is old) break;
    }
    return decl;
  }

  static bool isGenerator(Expr expr) {
    return expr.exprType.kind == GeneratorType.Kind;
  }

  override Node visit(MemberExpr expr) {
    accept(expr.expr);
    writefln("MemberExpr %s", expr.accept(ExprToString()));
    Decl decl;

    if (expr.expr.exprType) {
      decl = resolve(expr.expr.exprType);
    }
    if (!decl && cast(DeclExpr)(expr.expr)) {
      DeclExpr declExpr = cast(DeclExpr)(expr.expr);
      decl = declExpr.decl;
    }
    if (decl) {
      writefln("aaaa %s %s %s", decl, decl.declType, expr.identifier.value);
      if (cast(StructDecl)decl) {
        auto structDecl = cast(StructDecl)decl;
        auto ident = expr.identifier.value;
        foreach (field; structDecl.fields) {
          if (field.identifier.value == ident) {
            writefln("field %s", field.declType);
            expr.exprType = field.declType;
            //writefln("aaaaa %s %s %s", decl, expr.identifier.value, expr.exprType);
            return expr;
          }
        }
        error(expr.expr, "No field " ~ ident.idup ~ " in " ~ structDecl.identifier.value.idup);
        //return expr;
      }
    }

    error(expr.expr, "Cannot access members of " ~ typeid(expr.expr).toString());
    assert(0);

    //expr.exprType = expr.expr.exprType;


  }

	override Node visit(ScopeStmt stmt) {
		pushScope();
		accept(stmt.stmts);
		currentScope.print();
		popScope();
		return stmt;
	}

	override Node visit(Stmts stmts) {
		writefln("stmts %d [", stmts.stmts.length);
		foreach(ref stmt ; stmts.stmts) {
			accept(stmt);
		}
		writefln("]");
		return stmts;
	}

  override Node visit(FieldDecl decl) {
    writefln("FieldDecl");
    accept(decl.typeExpr);
    if (auto typeExpr = cast(DeclExpr)decl.typeExpr) {
      if (auto typeDecl = cast(TypeDecl)typeExpr.decl) {
        decl.declType = typeDecl.declType;
        return decl;
      }
    }
    error(decl.typeExpr, "Expected type");
    return decl;
  }

  override Node visit(VarDecl decl) {
    writefln("VarDecl %s", decl.name);
    accept(decl.typeExpr);
    if (auto typeExpr = cast(DeclExpr)decl.typeExpr) {
      if (auto typeDecl = cast(TypeDecl)typeExpr.decl) {
        decl.declType = typeDecl.declType;
        return decl;
      }
    }
    error(decl.typeExpr, "Expected type");
    return decl;
  }

  override Node visit(StructDecl decl) {
    writefln("StrucDecl");
    foreach(ref field; decl.fields)
      accept(field);
    return decl;
  }

	override Node visit(DeclStmt stmt) {

		accept(stmt.expr);
    accept(stmt.decl);

    //stmt.decl.declType = stmt.expr.exprType;
    writefln("DeclStmt %s %s %s", stmt.expr, stmt.decl, mangled(stmt.decl.declType));
		//if (!stmt.exprType) expr.exprType = expr.expr.exprType;
		//writefln("Add to symbol table: %s %s", stmt.identifier.value, mangled(stmt.decl.declType));
		// Add identifier to symbol table
		currentScope.define(stmt.identifier.value, stmt.decl);

		return stmt;
	}

	override Node visit(Program program) {
    writefln("program");
		pushScope();
		globalScope = currentScope;

    writefln("program");

    __gshared static auto freq = new StructType("frequency");
    __gshared static auto dur = new StructType("Duration");
    __gshared static auto Time = new StructType("Time");

    foreach(ref decl; program.decls) {
//      accept(decl);
      //NamedType type = cast(NamedType) decl.declType;
      globalScope.define(decl.name, decl);
    }
		//globalScope.define("Time", new NamedType("Time", new StructType()));
		globalScope.define("now", new VarDecl(Time, token(Identifier, "now")));
    globalScope.define("Duration", new TypeDecl(dur, token(Identifier, "Duration")));
    globalScope.define("mono", new TypeDecl(numberType, token(Identifier, "mono")));
    globalScope.define("float", new TypeDecl(numberType, token(Identifier, "float")));
		globalScope.define("frequency", new TypeDecl(freq, token(Identifier, "frequency")));
    globalScope.define("Time", new TypeDecl(Time, token(Identifier, "Time")));
    //globalScope.define("Float", new TypeDecl(new NamedType("Float", new StructType())));

		globalScope.define("hz", new VarDecl(new FunctionType(freq, [numberType]), token(Identifier, "hz")));
		globalScope.define("bpm", new VarDecl(new FunctionType(freq, [numberType]), token(Identifier, "bpm")));
    globalScope.define("ms", new VarDecl(new FunctionType(dur, [numberType]), token(Identifier, "ms")));
    globalScope.define("seconds", new VarDecl(new FunctionType(dur, [numberType]), token(Identifier, "seconds")));
    globalScope.define("samples", new VarDecl(new FunctionType(dur, [numberType]), token(Identifier, "samples")));

    foreach(ref decl; program.decls) {
      accept(decl);
      //NamedType type = cast(NamedType) decl.declType;
//      globalScope.define(decl.name, decl);
    }


		currentScope.print();

    init();
		writefln("pr");
		foreach (ref node ; program.nodes)
			accept(node);
		popScope();
		return program;
	}
}
