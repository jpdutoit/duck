module duck.compiler.semantic.decl;
import duck.compiler.buffer;
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

  Decl analyzeCallableParams(CallableDecl decl) {
    Type[] paramTypes;

    foreach(parameter; decl.parameters) {
        accept(parameter);
        paramTypes ~= parameter.declType;
    }

    semantic.symbolTable.pushScope(decl.parameters.readonly());
    if (decl.returnExpr) {
      accept(decl.returnExpr);
    }
    if (decl.callableBody) {
      semantic.symbolTable.pushScope(new DeclTable());
      accept(decl.callableBody);
      semantic.symbolTable.popScope();
    }
    semantic.symbolTable.popScope();

    debug(Semantic) log("=>", decl.parameterTypes, "->", decl.returnExpr);

    auto returnType = decl.returnExpr ? decl.returnExpr.exprType : TypeType.create(VoidType.create);
    return returnType.visit!(
      (TypeType t) {
        auto type = FunctionType.create(t.type, TupleType.create(paramTypes));
        type.decl = decl;
        decl.declType = type;
        debug(Semantic) log("=>", decl);
        return decl;
      },
      (Type t) {
        expect(!decl.callableBody, decl.returnExpr, "Cannot specify a function body along with an inline return expression");
        auto type = FunctionType.create(returnType, TupleType.create(paramTypes));
        type.decl = decl;
        decl.declType = type;
        decl.isMacro = true;
        debug(Semantic) log("=>", decl);
        return decl;
      }
    );
  }

   Node visit(CallableDecl decl) {
    return analyzeCallableParams(decl);
  }

  Node visit(ParameterDecl decl) {
    accept(decl.typeExpr);
    decl.declType = decl.typeExpr.decl.declType;
    if (decl.typeExpr.hasError) decl.taint();
    return decl;
  }

  Node visit(VarDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.typeExpr);

    if (!decl.typeExpr) {
      ASSERT(decl.valueExpr, "Internal compiler error: Expected at least one of typeExpr or valueExpr");
      accept(decl.valueExpr);
      decl.typeExpr = null;
      decl.declType = decl.valueExpr.exprType;
      return decl;
    }

    accept(decl.typeExpr);

    if (auto ce = decl.typeExpr.as!ConstructExpr) {
      if (!ce.callable) {
        decl.declType = ce.exprType;
        return decl;
      }

      decl.valueExpr = decl.typeExpr;
      auto callable = ce.callable.enforce!RefExpr().decl.as!CallableDecl;
      decl.typeExpr = callable.parentDecl.reference();
      decl.declType = callable.parentDecl.declType;
      accept(decl.typeExpr);
      return decl;
    }
    if (decl.typeExpr.hasError)
      return decl.taint();

    if (decl.typeExpr.exprType.kind == TypeType.Kind) {
      if (auto typeDecl = decl.typeExpr.getTypeDecl()) {
        decl.declType = typeDecl.declType;
        if (!decl.valueExpr) {
          decl.valueExpr = typeDecl.reference().call();
        }
        accept(decl.valueExpr);
        if (decl.valueExpr && decl.declType != decl.valueExpr.exprType && !decl.valueExpr.hasError) {
          error(decl.valueExpr, "Expected default value to be of type " ~ mangled(decl.declType) ~ " not of type " ~ mangled(decl.valueExpr.exprType) ~ ".");
          decl.valueExpr.taint();
        }

        return decl;
      }
    } else {
      //FIXME: Check that valueExpr is null
      Expr target = decl.typeExpr;
      TypeExpr contextType = new TypeExpr(decl.parentDecl.reference());
      auto mac = new CallableDecl(decl.name, contextType, [], target, decl.parentDecl);
      mac.isMacro = true;
      // Think of a nicer solution than replacing it in decls table,
      // perhaps the decls table should only be constructed after all the fields
      // have been analyzed
      decl.parentDecl.decls.replace(decl.name, mac);
      return mac;
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

    auto typeExpr = new TypeExpr(structDecl.reference());
    structDecl.context = new ParameterDecl(typeExpr, Slice("this"));
    accept(structDecl.context);

    DeclTable thisScope = new DeclTable();
    thisScope.define(structDecl.context);
    semantic.symbolTable.pushScope(thisScope);

    auto thisRef = structDecl.context.reference();
    accept(thisRef);
    semantic.symbolTable.pushScope(structDecl.decls, thisRef);

    ///FIXME
    foreach(name, ref decl; structDecl.decls.symbolsInDefinitionOrder) {
      if (cast(FieldDecl)decl)accept(decl);
    }

    foreach(name, ref decl; structDecl.decls.symbolsInDefinitionOrder) {
      if (cast(CallableDecl)decl && (cast(CallableDecl)decl).isMacro) accept(decl);
    }

    foreach(name, ref decl; structDecl.decls.symbolsInDefinitionOrder)
      if (cast(CallableDecl)decl && !(cast(CallableDecl)decl).isMacro) accept(decl);

    foreach(name, ref decl; structDecl.ctors.decls)
      if (cast(CallableDecl)decl && !(cast(CallableDecl)decl).isMacro) accept(decl);

    semantic.symbolTable.popScope();
    semantic.symbolTable.popScope();
    return structDecl;
  }
}
