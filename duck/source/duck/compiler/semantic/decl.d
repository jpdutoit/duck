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


  Node visit(AliasDecl decl) {
    accept(decl.value);
    decl.type = decl.value.type;
    return decl;
  }

  Node visit(DistinctDecl decl) {
    accept(decl.baseTypeExpr);
    if (auto meta = decl.baseTypeExpr.expect!MetaType)
      decl.type = MetaType.create(DistinctType.create(decl.name, meta.type));
    else return decl.taint;
    return decl;
  }

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
        decl.type = FunctionType.create(metaType.type, TupleType.create(paramTypes), decl);
        expect(decl.isExternal || decl.callableBody !is null, decl.returnExpr, "Function body expected");
      } else {
        expect(!decl.callableBody, decl.returnExpr, "Cannot specify a function body along with an inline return expression");
        decl.type = MacroType.create(decl.returnExpr.type, TupleType.create(paramTypes), decl);
      }
    } else {
      decl.type = FunctionType.create(VoidType.create, TupleType.create(paramTypes), decl);
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

  Node visit(BuiltinVarDecl decl) {
    return decl;
  }

  Node visit(VarDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.typeExpr);

    if (!decl.typeExpr && !decl.valueExpr) {
      throw __ICE("Expected at least one of typeExpr or valueExpr");
    }

    if (!decl.typeExpr) {
      accept(decl.valueExpr);
      exprSemantic.resolveValue(decl.valueExpr);
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
      if (decl.typeExpr.as!RefExpr && decl.typeExpr.as!RefExpr.decl.as!PropertyDecl) {

      } else {
        if (!decl.valueExpr)
          decl.valueExpr = new ConstructExpr(decl.typeExpr, [], decl.typeExpr.source);
        accept(decl.valueExpr);
        decl.valueExpr = exprSemantic.coerce(decl.valueExpr, metaType.type);
        decl.typeExpr = null;
      }
      return decl;
    }

    decl.typeExpr.expect!MetaType;
    return decl.taint;
  }

  Node visit(Decl decl) {
    return decl;
  }

  CallableDecl generateDefaultConstructor(StructDecl structDecl) {
      auto callable = new CallableDecl();
      callable.name = Slice("__ctor");
      callable.parent = structDecl;
      callable.isConstructor = true;
      callable.callableBody = new ScopeStmt();
      return callable;
  }

  Node visit(StructDecl structDecl) {
    debug(Semantic) log("=>", structDecl.name.blue);

    access.push(structDecl);

    if (auto outer = structDecl.parent.as!StructDecl) {
      AliasDecl a = new AliasDecl(Slice("outer"), new RefExpr(outer.context.elements[0]));
      accept(a);
      structDecl.members.define("outer", a);
    }

    foreach(decl; structDecl.context) {
      accept(decl);
    }

    semantic.symbolTable.pushScope(new StructScope(structDecl));

    if (structDecl.structBody)
    foreach(Stmt stmt; structDecl.structBody) {
      stmt.visit!(
        (DeclStmt stmt) {
          debug(Semantic) log("Add to symbol table:", stmt.decl.name, stmt.decl);

          if (!stmt.decl.as!CallableDecl && structDecl.members.defines(stmt.decl.name)) {
            error(stmt.decl.name, "Cannot redefine " ~ stmt.decl.name);
            return;
          }
          structDecl.members.define(stmt.decl.name, stmt.decl);
        },
        (Stmt stmt) {
          stmt.error("Statement unexpected as part of struct declarations");
        }
      );
    }

    import std.algorithm.iteration: filter;
    auto defaultCtors = structDecl.constructors.as!CallableDecl.filter!(c => c.parameters.length == 0);
    if (!structDecl.isExternal && defaultCtors.empty && !structDecl.as!PropertyDecl) {
      auto ctor = generateDefaultConstructor(structDecl);
      structDecl.members.define(ctor);
    }

    if (structDecl.structBody)
    foreach(Stmt stmt; structDecl.structBody) {
      stmt.visit!(
        (DeclStmt stmt) { accept(stmt.decl); },
        (Stmt stmt) { }
      );
    }
    semantic.symbolTable.popScope();
    access.pop();
    return structDecl;
  }

  Node visit(ImportDecl decl) {
    debug(Semantic) log("=>", decl.identifier.value);

    if (decl.identifier.length <= 2) {
      return decl.taint;
    }

    if (!decl.targetContext)
      decl.targetContext = context.createImportContext(decl.identifier[1..$-1]);

    if (decl.targetContext) {
      auto importee = stack.find!Library;
      if (auto library = decl.targetContext.library) {
        foreach(exported; library.exports) {
          import std.algorithm.searching: canFind;

          importee.imports.define(exported.name, exported);

          if (decl.attributes.visibility == Visibility.public_)
          if (!importee.exports.canFind(exported))
            importee.exports ~= exported;
        }
      }
      context.errors ~= decl.targetContext.errors;
      return decl;
    }
    return decl.taint;
  }
}
