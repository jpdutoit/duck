module duck.compiler.semantic.stmt;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
import duck.compiler.semantic.errors;
import duck.compiler.ast;
import duck.compiler.scopes;
import duck.compiler.lexer;
import duck.compiler.types;
import duck.compiler.visitors;
import duck.compiler.dbg;
import duck.compiler.context;
import duck;

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
    if (!stmt.decl.name) return stmt;

    this.symbolTable.define(stmt.decl.name, stmt.decl);

    if (this.symbolTable.top is this.library.globals
      && stmt.decl.visibility == Visibility.public_
      && !stmt.decl.hasError) {
      this.library.exports ~= stmt.decl;
    }

    return stmt;
  }

  Node visit(IfStmt stmt) {
    //TODO: Ensure that condition converts to boolean
    accept(stmt.condition);
    accept(stmt.trueBody);
    if (stmt.falseBody)
      accept(stmt.falseBody);
    return stmt;
  }

  Node visit(ImportStmt stmt) {
    import std.path, std.file, duck.compiler;
    debug(Semantic) log("=>", stmt.identifier.value);

    if (stmt.identifier.length <= 2) {
      context.error(stmt.identifier, "Expected path to package to not be empty.");
      return null;
    }

    if (!stmt.targetContext)
      stmt.targetContext = this.context.createImportContext(stmt.identifier[1..$-1]);

    if (stmt.targetContext) {
      if (auto library = stmt.targetContext.library) {
        foreach(decl; library.exports) {
          semantic.library.imports.define(decl.name, decl);
        }
      }
      semantic.context.errors ~= stmt.targetContext.errors;
      return stmt;
    }
    return null;
  }
}
