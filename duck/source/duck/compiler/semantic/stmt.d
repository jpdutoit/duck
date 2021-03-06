module duck.compiler.semantic.stmt;

import duck.compiler;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.errors;

struct StmtSemantic {
  SemanticAnalysis *semantic;
  alias semantic this;

  void accept(E)(ref E target) { semantic.accept!E(target);}

  Node visit(ExprStmt stmt) {
    if (auto declExpr = cast(InlineDeclExpr) stmt.expr) {
      accept(declExpr.declStmt);
      return declExpr.declStmt;
    }

    accept(stmt.expr);
    semantic.exprSemantic.resolveValue(stmt.expr);

    return stmt;
  }

  Node visit(ReturnStmt stmt) {
    if (stmt.value)
      accept(stmt.value);

    if (auto callable = this.stack.find!CallableDecl) {
      auto returnType = callable.type.as!FunctionType.returnType;
      if (returnType.as!VoidType) {
        if (stmt.value)
          error(stmt, "Cannot return a value from this function");
      }
      else  {
        if (stmt.value)
          stmt.value = coerce(stmt.value, returnType);
        else
          error(stmt, "Function must return a value");
      }

      if (stmt.next) {
        error(stmt.next, "Statement is not reachable");
      }
    } else {
      error(stmt, "Can only return from a function");
    }

    return stmt;
  }

  Node visit(BlockStmt block) {
    foreach(ref stmt; block) {
      debug(Semantic) log("'", stmt.source.toString().yellow, "'");
      accept(stmt);
      debug(Semantic) log("");
    }
    return block;
  }

  Node visit(ScopeStmt stmt) {
    symbolTable.pushScope(new BlockScope());
    visit(stmt.enforce!BlockStmt);
    symbolTable.popScope();
    return stmt;
  }

  Node visit(DeclStmt stmt) {
    accept(stmt.decl);
    debug(Semantic) log("=>", stmt.decl);

    debug(Semantic) log("Add to symbol table:", stmt.decl.name, stmt.decl.type.mangled);

    if (!stmt.decl.as!CallableDecl && this.symbolTable.top.defines(stmt.decl.name)) {
      error(stmt.decl.name, "Cannot redefine " ~ stmt.decl.name);
      return stmt;
    }

    // Don't add unnamed variables to symboltable
    if (stmt.decl.name.length == 0) return stmt;

    this.symbolTable.define(stmt.decl.name, stmt.decl);

    auto library = stack.find!Library;
    if (cast(FileScope)this.symbolTable.top
      && stmt.decl.visibility == Visibility.public_
      && !stmt.decl.hasError) {
      library.exports ~= stmt.decl;
    }

    return stmt;
  }

  Node visit(IfStmt stmt) {
    accept(stmt.condition);
    stmt.condition = coerce(stmt.condition, BoolType.create);
    accept(stmt.trueBody);
    if (stmt.falseBody)
      accept(stmt.falseBody);
    return stmt;
  }

  Node visit(WithStmt stmt) {
    accept(stmt.valueExpr);
    semantic.symbolTable.pushScope(new WithScope(stmt.valueExpr));
    accept(stmt.withBody);
    semantic.symbolTable.popScope();
    return stmt;
  }
}
