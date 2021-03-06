module duck.compiler.semantic;

import duck.util.stack;

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
  Stack!Decl access;

  Expr[Decl] implicitContexts;

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
    if (target.hasType) return;
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
    if (target.semantic) return;

    debug(Semantic) {
      logIndent();
      log(target.prettyName.red, target, "'" ~ target.name ~ "'");
    }

    stack.push(target);
    target.semantic = true;
    Decl obj = cast(Decl)target.accept(declSemantic);
    obj.semantic = true;
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

  Visibility accessLevel(StructType type) {
    return access.find(type.decl) is null ? Visibility.public_ : Visibility.private_;
  }

  void semantic(Library library) {
    access.push(library);
    stack.push(library);
    symbolTable.pushScope(new ImportScope(library.imports));
    symbolTable.pushScope(new FileScope(library.globals));
    accept(library.stmts);
    symbolTable.popScope();
    symbolTable.popScope();
    stack.pop();
    access.pop();
  }
}
