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

  Node visit(VarDeclStmt stmt) {
    //debug(Semantic) log("=>", stmt.expr);
    if (stmt.expr) {
      accept(stmt.expr);
      debug(Semantic) log("=>", stmt.expr);
    }
    accept(stmt.decl);
    debug(Semantic) log("=>", stmt.decl);

    debug(Semantic) log("Add to symbol table:", stmt.identifier.value, mangled(stmt.decl.declType));
    // Add identifier to symbol table
    if (symbolTable.defines(stmt.identifier.value)) {
      error(stmt.identifier, "Cannot redefine " ~ stmt.identifier.value.idup);
    }
    else {
      symbolTable.define(stmt.identifier.value, stmt.decl);
    }

    if (stmt.decl.declType.kind != ErrorType.Kind) {
      library.exports ~= stmt.decl;
    }

    return stmt;
  }


  Node visit(TypeDeclStmt stmt) {
    accept(stmt.decl);
    
    if (!cast(CallableDecl)stmt.decl && globalScope.defines(stmt.decl.name)) {
      error(stmt.decl.name, "Cannot redefine " ~ stmt.decl.name.idup);
    }
    else {
      globalScope.define(stmt.decl.name, stmt.decl);
    }

    if (stmt.decl.declType.kind != ErrorType.Kind) {
      library.exports ~= stmt.decl;
    }
    return stmt;
  }

  Node visit(ImportStmt stmt) {
    import std.path, std.file, duck.compiler;
    debug(Semantic) log("=>", stmt.identifier.value);

    if (stmt.identifier.length <= 2) {
      context.error(stmt.identifier, "Expected path to package to not be empty.");
      return new Stmts([]);
    }

    auto paths = ImportPaths(stmt.identifier[1..$-1], sourcePath, context.packageRoots);
    string lastPath;
    foreach (i, string path ; paths) {
      lastPath = path;
      if (path.exists()) {
        Context context  = Duck.contextForFile(path);
        stmt.targetContext = context;
        if (i == 0)
          context.includePrelude = false;

        context.verbose = semantic.context.verbose;

        auto library = context.library;

        if (library) {
          foreach(decl; library.exports) {
            semantic.library.imports.define(decl.name, decl);
          }
        }

        semantic.context.errors += context.errors;
        semantic.context.dependencies ~= context;

        return stmt;
      }
    }
    context.error(stmt.identifier, "Cannot find library at '%s'", lastPath);
    //return stmt;
    return new Stmts([]);
  }
}
