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
    if (decl.callableBody) {
      semantic.symbolTable.pushScope(new DeclTable());
      accept(decl.callableBody);
      semantic.symbolTable.popScope();
    }
    semantic.symbolTable.popScope();

    debug(Semantic) log("=>", decl.parameterTypes, "->", decl.returnExpr);

    if (decl.returnExpr) {
      if (auto metaType = decl.returnExpr.type.as!MetaType) {
        decl.type = FunctionType.create(metaType.type, TupleType.create(paramTypes));
      } else {
        expect(!decl.callableBody, decl.returnExpr, "Cannot specify a function body along with an inline return expression");
        decl.isMacro = true;
        decl.type = FunctionType.create(decl.returnExpr.type, TupleType.create(paramTypes));
      }
    } else {
      decl.type = FunctionType.create(VoidType.create, TupleType.create(paramTypes));
    }
    return decl;
  }

  Node visit(ParameterDecl decl) {
    accept(decl.typeExpr);
    decl.type = decl.typeExpr.decl.declaredType;
    if (decl.typeExpr.hasError) decl.taint();
    return decl;
  }

  Node visit(VarDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.typeExpr);

    if (!decl.typeExpr && !decl.valueExpr) {
      ASSERT(decl.valueExpr, "Internal compiler error: Expected at least one of typeExpr or valueExpr");
    }

    if (!decl.typeExpr) {
      accept(decl.valueExpr);
      decl.type = decl.valueExpr.type;
      return decl;
    }

    accept(decl.typeExpr);

    if (auto ce = decl.typeExpr.as!ConstructExpr) {
      if (!ce.callable) {
        decl.type = ce.type;
        return decl;
      }

      decl.valueExpr = decl.typeExpr;
      auto callable = ce.callable.enforce!RefExpr().decl.as!CallableDecl;
      decl.typeExpr = callable.parentDecl.reference();
      decl.type = callable.parentDecl.declaredType;
      accept(decl.typeExpr);
      return decl;
    }
    if (decl.typeExpr.hasError)
      return decl.taint();

    if (decl.typeExpr.type.kind == MetaType.Kind) {
      if (auto typeDecl = decl.typeExpr.getTypeDecl()) {
        decl.type = typeDecl.declaredType;
        if (!decl.valueExpr) {
          decl.valueExpr = typeDecl.reference().call();
        }
        accept(decl.valueExpr);
        if (decl.valueExpr && decl.type != decl.valueExpr.type && !decl.valueExpr.hasError) {
          error(decl.valueExpr, "Expected default value to be of type " ~ mangled(decl.type) ~ " not of type " ~ mangled(decl.valueExpr.type) ~ ".");
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

    if (!decl.type) {
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
