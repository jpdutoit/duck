module duck.compiler.semantic;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;//, duck.compiler.transforms;
import duck.compiler.visitors, duck.compiler.context;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.semantic.helpers;
import duck;

import duck.compiler.semantic.decl;
import duck.compiler.semantic.expr;
import duck.compiler.semantic.stmt;

import std.stdio;
//debug = Semantic;
debug = Trace;

protected:

public:

string prettyName(T)(ref T t) {
  import std.regex;
  return t.classinfo.name.replaceFirst(regex(r"^.*\."), "");
}


Expr error(Expr expr, string message) {
  Context.current.error(expr.findSource(), message);
  return expr.taint;
}

void error(Token token, string message) {
  Context.current.error(token, message);
}

bool expect(T)(T expectation, Expr expr, lazy string message) {
  if (!expectation) {
    error(expr, message);
    return false;
  }
  return true;
}

struct SemanticAnalysis {
  ExprSemantic exprSemantic;
  StmtSemantic stmtSemantic;
  DeclSemantic declSemantic;

  void accept(E : Stmt)(ref E target) {
    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target);
    }
    auto obj = target.accept(stmtSemantic);
    debug(Semantic) logOutdent();

    ASSERT(cast(E)obj, "expected StmtSemantic.visit(" ~ target.prettyName ~ ") to return a " ~ Expr.stringof ~ " and not a " ~ obj.prettyName);
    target = cast(E)obj;
  }

  void accept(E : Expr)(ref E target) {
    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target);
    }
    auto obj = target.accept(exprSemantic);
    debug(Semantic) {
      log("=>", obj);
      logOutdent();
    }
    ASSERT(cast(E)obj, "expected ExprSemantic.visit(" ~ target.prettyName ~ ") to return a " ~ Expr.stringof ~ " and not a " ~ obj.prettyName);
    target = cast(E)obj;
  }

  void accept(E : Decl)(ref E target) {
    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target);
    }
    auto obj = target.accept(declSemantic);
    debug(Semantic)  logOutdent();

    ASSERT(cast(E)obj, "expected DeclSemantic.visit(" ~ target.prettyName ~ ") to return a " ~ Expr.stringof ~ " and not a " ~ obj.prettyName);
    target = cast(E)obj;
  }

  void accept(N)(ref N node) {
    //if (cast(Expr)node) accept!Expr(node);
    //else if (cast(Stmt)node) accept!Stmt(node);
    //else if (cast(Decl)node) accept!Decl(node);

    auto obj = node.accept(this);
  }

  alias accept2 = accept;

  SymbolTable symbolTable;
  Scope globalScope;
  string sourcePath;

  Context context;


  this(Context context, string sourcePath) {
    this.symbolTable = new SymbolTable();
    this.context = context;
    this.sourcePath = sourcePath;
    exprSemantic = ExprSemantic(&this);
    stmtSemantic = StmtSemantic(&this);
    declSemantic = DeclSemantic(&this);
  }

  Stmt[] splitStatements;

  void splitStatement(Stmt stmt) {
    splitStatements ~= stmt;
  }

  Library library;

  Node visit(Library library) {
    this.library = library;

    symbolTable.pushScope(library.imports);
    symbolTable.pushScope(new DeclTable());
    globalScope = symbolTable.scopes[1];

    globalScope.define("mono", new TypeDecl(NumberType.create, context.token(Identifier, "mono")));
    globalScope.define("float", new TypeDecl(NumberType.create, context.token(Identifier, "float")));
    globalScope.define("string", new TypeDecl(StringType.create, context.token(Identifier, "string")));

    foreach (ref node ; library.nodes)
      accept(node);

    symbolTable.popScope();
    symbolTable.popScope();
    debug(Semantic) log("Done");
    return library;
  }
}
