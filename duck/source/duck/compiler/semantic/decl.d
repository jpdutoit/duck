module duck.compiler.semantic.decl;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.ast;
import duck.compiler.scopes;
import duck.compiler.lexer;
import duck.compiler.types;
import duck.compiler.visitors;
import duck.compiler.dbg;

struct DeclSemantic {
  SemanticAnalysis *semantic;

  alias semantic this;

  void accept(E)(ref E target) { semantic.accept!E(target); }

  Node visit(UnboundDecl decl) {
    return decl;
  }

  Node visit(MacroDecl decl) {
    if (decl.contextType)
      accept(decl.contextType);
    Type[] paramTypes;
    for (int i = 0; i < decl.parameterTypes.length; ++i) {
      accept(decl.parameterTypes[i]);
      paramTypes ~= decl.parameterTypes[i].decl.declType;
    }
    debug(Semantic) log("=>", decl.parameterTypes);

    auto type = FunctionType.create(decl.expansion.exprType, TupleType.create(paramTypes));
    type.decl = decl;
    decl.declType = type;
    debug(Semantic) log("=>", decl.declType.describe);

    debug(Semantic) log("=> expansion", decl.expansion);
    return decl;
  }

  Decl analyzeCallableParams(CallableDecl decl) {
    auto paramScope = new DeclTable();
    Type[] paramTypes;

    bool parentIsExternal = false;
    StructDecl parentDecl = null;
    if (auto md = cast(MethodDecl)decl) {
      parentDecl = md.parentDecl;
      if (md.parentDecl.external) parentIsExternal = true;
    }

    for (int i = 0; i < decl.parameterTypes.length; ++i) {
      accept(decl.parameterTypes[i]);
      Type paramType = decl.parameterTypes[i].decl.declType;
      paramTypes ~= paramType;

      if (!decl.external && !parentIsExternal) {
        Token name = decl.parameterIdentifiers[i];
        paramScope.define(name.value, new UnboundDecl(paramType, name));
      }
    }

    if (parentDecl) {
      //auto thisToken = semantic.context.token(Identifier, "this");
      paramScope.define("this", new UnboundDecl(parentDecl.declType, None));
    }

    semantic.symbolTable.pushScope(paramScope);
    if (decl.returnExpr) {
      accept(decl.returnExpr);
    }
    if (decl.callableBody) {
      accept(decl.callableBody);
    }
    semantic.symbolTable.popScope();

    debug(Semantic) log("=>", decl.parameterTypes, "->", decl.returnExpr);

    auto returnType = decl.returnExpr ? decl.returnExpr.exprType : TypeType.create(VoidType.create);
    return returnType.visit!(
      (TypeType t) {
        auto type = FunctionType.create(t.type, TupleType.create(paramTypes));
        type.decl = decl;
        decl.declType = type;
        return decl;
      },
      (Type t) {
        expect(!decl.callableBody, decl.returnExpr, "Cannot specify a function body along with an inline return expression");
        auto mac = new MacroDecl(decl.name, decl.contextType, decl.parameterTypes, decl.parameterIdentifiers, decl.returnExpr, parentDecl);
        this.accept(mac);
        return mac;
      }
    );
  }

  Node visit(FunctionDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.parameterTypes, "->", decl.returnExpr);

    return analyzeCallableParams(decl);

    /*if (decl.functionBody) {
      semantic.symbolTable.pushScope(paramScope);
      accept(decl.functionBody);
      semantic.symbolTable.popScope();
    }*/


  }

   Node visit(MethodDecl decl) {

    return analyzeCallableParams(decl);
    /*if (decl.methodBody) {
      auto thisToken = semantic.context.token(Identifier, "this");
      paramScope.define("this", new UnboundDecl(decl.parentDecl.declType, thisToken));

      semantic.symbolTable.pushScope(paramScope);
      accept(decl.methodBody);
      semantic.symbolTable.popScope();
    }*/

  }


  Node visit(FieldDecl decl) {
    // Have to define "this" as unbound because the valu expression might actually be
    // a macro value expression.

    DeclTable funcScope = new DeclTable();
    Token thisToken = semantic.context.token(Identifier, "this");
    debug(Semantic) log("=> expansion", decl.typeExpr);
    Decl thisVar = new UnboundDecl(decl.parentDecl.declType, thisToken);
    //thisVar.accept(this);
    funcScope.define("this", thisVar);
    semantic.symbolTable.pushScope(funcScope);
    accept(decl.typeExpr);
    semantic.symbolTable.popScope();
    debug(Semantic) log("=> expansion", decl.typeExpr);

    if (decl.valueExpr)
      accept(decl.valueExpr);

    if (decl.typeExpr.exprType.kind == TypeType.Kind) {
      if (auto typeDecl = decl.typeExpr.getTypeDecl()) {
        decl.declType = typeDecl.declType;
        if (decl.valueExpr && decl.declType != decl.valueExpr.exprType && !decl.valueExpr.hasError) {
          error(decl.valueExpr, "Expected default value to be of type " ~ mangled(decl.declType) ~ " not of type " ~ mangled(decl.valueExpr.exprType) ~ ".");
          decl.valueExpr.taint();
        }

        return decl;
      }
    } else {
      //FIXME: Check that valueExpr is null
      Expr target = decl.typeExpr;
      TypeExpr contextType = new TypeExpr(new RefExpr(thisToken, decl.parentDecl));
      auto mac = new MacroDecl(decl.name, contextType, [], [], target, decl.parentDecl);
      // Think of a nicer solution than replacing it in decls table,
      // perhaps the decls table should only be constructed after all the fields
      // have been analyzed
      decl.parentDecl.decls.replace(decl.name, mac);
      return mac;
    }

    decl.taint();
    error(decl.typeExpr, "Expected type");
    return decl;
  }

  Node visit(VarDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.typeExpr);

    if (decl.typeExpr) {
      accept(decl.typeExpr);

      if (!decl.typeExpr.hasError) {
        if (auto typeExpr = cast(TypeExpr)decl.typeExpr) {
          decl.declType = typeExpr.decl.declType;
          return decl;
        }
      }
    }
    if (!decl.declType) {
      decl.taint();
      if (!decl.typeExpr.hasError)
        error(decl.typeExpr, "Expected type");
      }
    return decl;
  }

  Node visit(StructDecl structDecl) {
    debug(Semantic) log("=>", structDecl.name.blue);
    semantic.symbolTable.pushScope(structDecl.decls);
    ///FIXME
    foreach(name, ref decl; structDecl.decls.symbolsInDefinitionOrder) {
      if (cast(FieldDecl)decl)accept(decl);
    }
    foreach(name, ref decl; structDecl.decls.symbolsInDefinitionOrder) {
      if (cast(MacroDecl)decl)accept(decl);
    }
    foreach(name, ref decl; structDecl.decls.symbolsInDefinitionOrder)
      if (cast(MethodDecl)decl)accept(decl);
    foreach(name, ref decl; structDecl.ctors.decls)
      if (cast(MethodDecl)decl)accept(decl);
    semantic.symbolTable.popScope();
    return structDecl;
  }
}
