module duck.compiler.semantic.decl;

import duck.compiler;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.errors;
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
      semantic.symbolTable.pushScope(new BlockScope());
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
        decl.type = MacroType.create(decl.returnExpr.type, TupleType.create(paramTypes), decl);
      }
    } else {
      decl.type = FunctionType.create(VoidType.create, TupleType.create(paramTypes));
    }
    return decl;
  }

  Node visit(ParameterDecl decl) {
    accept(decl.typeExpr);
    if (decl.typeExpr.hasError) { return decl.taint(); }
    decl.type = decl.typeExpr.decl.declaredType;

    return decl;
  }

  Node visit(VarDecl decl) {
    debug(Semantic) log("=>", decl.name, decl.typeExpr);

    if (!decl.typeExpr && !decl.valueExpr) {
      throw __ICE("Expected at least one of typeExpr or valueExpr");
    }

    if (!decl.typeExpr) {
      if (!decl.valueExpr.hasType)
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
          decl.valueExpr = typeDecl.reference().withSource(decl.typeExpr.source).call();
        }
        accept(decl.valueExpr);
        decl.valueExpr = exprSemantic.coerce(decl.valueExpr, decl.type);
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
      decl.parentDecl.members.replace(decl.name, mac);
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

    structDecl.context = new ParameterDecl(new TypeExpr(structDecl.reference()), Slice("this"));
    accept(structDecl.context);

    semantic.symbolTable.pushScope(new ThisScope(structDecl));

    foreach(ref decl; structDecl.fields) accept(decl);
    foreach(ref decl; structDecl.macros) accept(decl);
    foreach(ref decl; structDecl.methods) accept(decl);
    foreach(ref decl; structDecl.constructors) accept(decl);

    semantic.symbolTable.popScope();
    return structDecl;
  }
}
