module duck.compiler.semantic;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;
import duck.compiler.visitors, duck.compiler.context;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.semantic.helpers;
import duck;

import duck.compiler.semantic.decl;
import duck.compiler.semantic.expr;
import duck.compiler.semantic.stmt;
import duck.compiler.semantic.errors;
public import duck.compiler.context: context;

import std.stdio;
//debug = Semantic;
debug = Trace;

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

  void accept(N)(ref N node) {
    //if (cast(Expr)node) accept!Expr(node);
    //else if (cast(Stmt)node) accept!Stmt(node);
    //else if (cast(Decl)node) accept!Decl(node);

    auto obj = node.accept(this);
  }

  alias accept2 = accept;

  SymbolTable symbolTable;
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

  Library library;

  Node visit(Library library) {
    this.library = library;

    symbolTable.pushScope(library.imports);

    library.globals.define("int", new TypeDecl(IntegerType.create, "int"));
    library.globals.define("mono", new TypeDecl(FloatType.create, "mono"));
    library.globals.define("float", new TypeDecl(FloatType.create, "float"));
    library.globals.define("string", new TypeDecl(StringType.create, "string"));

    symbolTable.pushScope(library.globals);

    accept(library.stmts);

    symbolTable.popScope();
    symbolTable.popScope();
    debug(Semantic) log("Done");
    return library;
  }
}
