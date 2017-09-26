module duck.compiler.semantic;

import duck.compiler;
import duck.compiler.visitors;
import duck.compiler.semantic.helpers;

import duck.compiler.semantic.decl;
import duck.compiler.semantic.expr;
import duck.compiler.semantic.stmt;
import duck.compiler.semantic.errors;

import std.stdio;
//debug = Semantic;

protected:

public:

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

  Stack!Node stack;

  void accept(E : Stmt)(ref E target) {
    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target);
    }
    stack.push(target);
    auto obj = target.accept(stmtSemantic);
    stack.pop();
    debug(Semantic) logOutdent();

    ASSERT(!obj || cast(E)obj, "expected StmtSemantic.visit(" ~ target.prettyName ~ ") to return a " ~ E.stringof ~ " and not a " ~ obj.prettyName);
    target = cast(E)obj;
  }

  void accept(E : Expr)(ref E target) {
    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target);
    }
    stack.push(target);
    auto obj = target.accept(exprSemantic);
    stack.pop();
    debug(Semantic) {
      log("=>", obj);
      logOutdent();
    }
    ASSERT(cast(E)obj, "expected ExprSemantic.visit(" ~ target.prettyName ~ ") to return a " ~ E.stringof ~ " and not a " ~ obj.prettyName);
    target = cast(E)obj;
  }

  void accept(E : Decl)(ref E target) {
    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target, "'" ~ target.name ~ "'");
    }
    stack.push(target);
    auto obj = target.accept(declSemantic);
    stack.pop();
    debug(Semantic)  logOutdent();

    ASSERT(cast(E)obj, "expected DeclSemantic.visit(" ~ target.prettyName ~ ") to return a " ~ E.stringof ~ " and not a " ~ obj.prettyName);
    target = cast(E)obj;
  }

  alias accept2 = accept;

  SymbolTable symbolTable;

  this(Context context) {
    this.symbolTable = new SymbolTable();
    exprSemantic = ExprSemantic(&this);
    stmtSemantic = StmtSemantic(&this);
    declSemantic = DeclSemantic(&this);
  }


  Expr coerce(Expr sourceExpr, Type targetType) {
    return exprSemantic.coerce(sourceExpr, targetType);
  }

  void semantic(Library library) {
    stack.push(library);
    symbolTable.pushScope(library.imports);
    symbolTable.pushScope(library.globals);
    accept(library.stmts);
    symbolTable.popScope();
    symbolTable.popScope();
    stack.pop();
  }
}
