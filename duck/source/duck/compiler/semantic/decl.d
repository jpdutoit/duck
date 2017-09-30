module duck.compiler.semantic.decl;

import duck.compiler;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.errors;
import duck.compiler.visitors;
import duck.compiler.dbg;

struct DeclSemantic {
  SemanticAnalysis *semantic;

  alias semantic this;

  void accept(E)(ref E target) { semantic.accept!E(target); }

  Node visit(CallableDecl decl) {
    Type[] paramTypes;

    foreach(parameter; decl.parameters) {
      accept(parameter);
      paramTypes ~= parameter.type;
    }

    semantic.symbolTable.pushScope(decl.parameters.readonly());
    if (decl.returnExpr) {
      accept(decl.returnExpr);
    }

    if (decl.returnExpr) {
      if (auto metaType = decl.returnExpr.type.as!MetaType) {
        decl.type = FunctionType.create(metaType.type, TupleType.create(paramTypes));
      } else {
        expect(!decl.callableBody, decl.returnExpr, "Cannot specify a function body along with an inline return expression");
        decl.isMacro = true;
        decl.type = MacroType.create(decl.returnExpr.type, TupleType.create(paramTypes), decl);
      }
    } else {
      decl.type = FunctionType.create(VoidType.create, TupleType.create(paramTypes));
    }

    if (decl.callableBody) {
      semantic.symbolTable.pushScope(new BlockScope());
      accept(decl.callableBody);
      semantic.symbolTable.popScope();
    }
    semantic.symbolTable.popScope();
    return decl;
  }

  Node visit(ParameterDecl decl) {
    accept(decl.typeExpr);
    if (auto meta = decl.typeExpr.expect!MetaType)
      decl.type = meta.type;
    else return decl.taint;

    return decl;
  }

  Node visit(VarDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.typeExpr);

    if (!decl.typeExpr && !decl.valueExpr) {
      throw __ICE("Expected at least one of typeExpr or valueExpr");
    }

    if (!decl.typeExpr) {
      accept(decl.valueExpr);
      decl.type = decl.valueExpr.type;
      return decl;
    }

    accept(decl.typeExpr);
    if (decl.typeExpr.hasError)
      return decl.taint();

    if (decl.typeExpr.as!ConstructExpr) {
      decl.type = decl.typeExpr.type;
      decl.valueExpr = decl.typeExpr;
      decl.typeExpr = null;
      return decl;
    }
    else if (auto metaType = decl.typeExpr.type.as!MetaType) {
      decl.type = metaType.type;
      if (!decl.valueExpr)
        decl.valueExpr = new ConstructExpr(decl.typeExpr, [], decl.typeExpr.source);
      accept(decl.valueExpr);
      decl.valueExpr = exprSemantic.coerce(decl.valueExpr, metaType.type);
      decl.typeExpr = null;
      return decl;
    }
    else if (auto structDecl = decl.parent.as!StructDecl) {
      expect(!decl.valueExpr, decl.valueExpr, "Unexpected value in alias declaration");
      Expr target = decl.typeExpr;
      auto mac = new CallableDecl(decl.name, target, structDecl);
      mac.isMacro = true;
      // Think of a nicer solution than replacing it in decls table,
      // perhaps the decls table should only be constructed after all the fields
      // have been analyzed
      structDecl.members.replace(decl.name, mac);
      structDecl.publicMembers.replace(decl.name, mac);
      return mac;
    } else {
      decl.typeExpr.expect!MetaType;
      return decl.taint;
    }
  }

  Node visit(BasicTypeDecl decl) {
    return decl;
  }

  CallableDecl generateDefaultConstructor(StructDecl structDecl) {
      auto callable = new CallableDecl();
      callable.name = Slice("__ctor");
      callable.parent = structDecl;
      callable.isConstructor = true;
      callable.isMethod = false;
      callable.callableBody = new ScopeStmt();
      return callable;
  }

  Node visit(StructDecl structDecl) {
    debug(Semantic) log("=>", structDecl.name.blue);

    access.push(structDecl);
    structDecl.context = new ParameterDecl(structDecl.reference(), Slice("this"));
    accept(structDecl.context);

    semantic.symbolTable.pushScope(new ThisScope(structDecl));

    import std.algorithm.iteration: filter;
    auto defaultCtors = structDecl.constructors.as!CallableDecl.filter!(c => c.parameters.length == 0);
    if (!structDecl.isExternal && defaultCtors.empty) {
      auto ctor = generateDefaultConstructor(structDecl);
      structDecl.members.define(ctor);
      structDecl.publicMembers.define(ctor);
    }

    foreach(ref decl; structDecl.fields) accept(decl);
    foreach(ref decl; structDecl.macros) accept(decl);
    foreach(ref decl; structDecl.methods) accept(decl);
    foreach(ref decl; structDecl.constructors) accept(decl);

    semantic.symbolTable.popScope();
    access.pop();
    return structDecl;
  }
}
