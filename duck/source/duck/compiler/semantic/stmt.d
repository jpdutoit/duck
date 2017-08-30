module duck.compiler.semantic.stmt;
import duck.compiler.semantic;
import duck.compiler.semantic.helpers;
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
    accept(stmt.expr);
    return stmt;
  }

  Node visit(ScopeStmt stmt) {
    symbolTable.pushScope(new DeclTable);
    accept(stmt.stmts);
    symbolTable.popScope();
    return stmt;
  }

  Node visit(Stmts stmts) {
    import duck.compiler.visitors.source;

    foreach(ref stmt ; stmts.stmts) {
      splitStatements = [];
      debug(Semantic) log("'", stmt.findSource().toString().yellow, "'");
      accept(stmt);
      debug(Semantic) log("");
      if (splitStatements.length > 0) {
        stmt = new Stmts(splitStatements ~ stmt);
      }
      splitStatements = null;
    }
    return stmts;
  }

  Node visit(DeclStmt stmt) {
    accept(stmt.decl);
    debug(Semantic) log("=>", stmt.decl);

    stmt.decl.visit!(
      delegate(VarDecl decl) {
        auto name = stmt.decl.name;
        debug(Semantic) log("Add to symbol table:", name, stmt.decl.type.mangled);

        if (this.symbolTable.defines(name)) {
          error(name, "Cannot redefine " ~ name);
        }
        else {
          this.symbolTable.define(name, stmt.decl);
          if (this.symbolTable.top is this.library.globals) {
            this.library.exports ~= stmt.decl;
          }
        }
      },
      delegate(CallableDecl decl) {
        this.library.globals.define(stmt.decl.name, stmt.decl);
        if (!stmt.decl.hasError) {
          this.library.exports ~= stmt.decl;
        }
      },
      delegate(TypeDecl decl) {
        if (this.library.globals.defines(stmt.decl.name)) {
          error(decl.name, "Cannot redefine " ~ stmt.decl.name);
        } else {
          this.library.globals.define(stmt.decl.name, stmt.decl);
        }
        if (!stmt.decl.hasError) {
          this.library.exports ~= stmt.decl;
        }
      }
    );

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
      return new Stmts([]);
    }

    if (!stmt.targetContext)
      stmt.targetContext = this.context.createImportContext(stmt.identifier[1..$-1]);

    if (stmt.targetContext) {
      if (auto library = stmt.targetContext.library) {
        foreach(decl; library.exports) {
          semantic.library.imports.define(decl.name, decl);
        }
      }
      semantic.context.errors ~= context.errors;
      return stmt;
    }

    return new Stmts([]);
  }
}
