module duck.compiler.ast;

import duck.compiler.lexer, duck.compiler.types, duck.compiler.semantic;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;
private import std.typecons: Rebindable;
alias NodeTypes = AliasSeq!(
  ErrorExpr,
  RefExpr,
  TypeExpr,
  InlineDeclExpr,
  ArrayLiteralExpr,
  LiteralExpr,
  IdentifierExpr,
  UnaryExpr,
  AssignExpr,
  BinaryExpr,
  PipeExpr,
  MemberExpr,
  CallExpr,
  TupleExpr,

  ExprStmt,
  VarDeclStmt,
  TypeDeclStmt,
  ScopeStmt,
  ImportStmt,
  Stmts,

  Decl,
  OverloadSet,
  FunctionDecl,
  VarDecl,
  TypeDecl,
  ConstDecl,
  FieldDecl,
  MethodDecl,
  StructDecl,
  AliasDecl,
  MacroDecl,

  Library);

mixin template NodeMixin() {
  static enum _nodeTypeId = staticIndexOf!(typeof(this), NodeTypes);
  static if (_nodeTypeId < 0) {
    //#TODO:0 Do it right
    static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in NodeTypes list.");
  }
  override NodeType nodeType() { return _nodeTypeId; };
};

abstract class Node {
  alias NodeType = ubyte;
  this() {
    //writefln("%s %s", this, &this);
  }
  NodeType nodeType();
};

abstract class Stmt : Node {
};

class Library : Node {
  mixin NodeMixin;

  Node[] nodes;
  DeclTable imports;
  Decl[] exports;

  this(Node[] nodes) {
    this.imports = new DeclTable();
    this.nodes = nodes;
  }
}

abstract class Decl : Node {
  mixin NodeMixin;

  Token name;
  //Expr expr;
  //Rebindable!(immutable Type) varType;
  //Token identifier;
  Type declType;

  this(Type type, Token name) {
    this.name = name;
    this.declType = type;
  }

  this(Token name) {
    this.name = name;
  }

}

class OverloadSet : Decl {
  mixin NodeMixin;

  CallableDecl[] decls;

  void add(CallableDecl decl) {
    decls ~= decl;
  }

  this(Token name) {
    super(OverloadSetType.create(this), name);
  }
}

class AliasDecl : Decl {
  mixin NodeMixin;

  Expr targetExpr;

  this(Token identifier, Expr targetExpr) {
    super(null, identifier);
    this.targetExpr = targetExpr;
  }
}

class MacroDecl : CallableDecl {
  mixin NodeMixin;

  Expr expansion;
  alias argTypes = parameterTypes;
  alias argNames = parameterIdentifiers;
  alias typeExpr = returnType;


  this(TypeExpr typeExpr, Token identifier, TypeExpr[] argTypes, Token[] argNames, Expr expansion) {
    super(identifier);
    this.typeExpr = typeExpr;
    this.argTypes = argTypes;
    this.argNames = argNames;
    this.expansion = expansion;
  }
}

class FieldDecl : Decl{
  mixin NodeMixin;

  TypeExpr typeExpr;
  alias identifier = name;
  Expr valueExpr;
  StructDecl parentDecl;

  this(TypeExpr typeExpr, Token identifier, Expr valueExpr, StructDecl parent) {
    super(null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = valueExpr;
    this.parentDecl = parent;
  }
}

class CallableDecl : Decl {
  Stmt callableBody;
  TypeExpr[] parameterTypes;
  Token[] parameterIdentifiers;
  TypeExpr returnType;
  bool external;

  this(Token identifier) {
    super(identifier);
  }
}

class FunctionDecl : CallableDecl {
  mixin NodeMixin;

  alias functionBody = callableBody;

  this(Token identifier) {
    super(identifier);
  }
}


class MethodDecl : CallableDecl {
  mixin NodeMixin;

  alias methodBody = callableBody;
  Decl parentDecl;

  this(Type type, Token identifier, Stmt methodBody, Decl parent) {
    super(identifier);
    this.declType = type;
    this.methodBody = methodBody;
    this.parentDecl = parent;
  }
}

class StructDecl : TypeDecl {
  mixin NodeMixin;

  /// Testing
  DeclTable decls;
  alias decls this;

  bool external;

  this(Type type, Token name) {
    super(type, name);
    decls = new DeclTable();
  }
}

/*class FuncDecl : Decl {
  mixin NodeMixin;
  bool external;
  Stmt funcBody;

  this(Type type, Token identifier, Stmt methodBody, Decl parent) {
    super(type, identifier);
    this.methodBody = methodBody;
    this.parentDecl = parent;
  }
}*/
/*class FuncDecl : Decl {
  Token identifier;
  Type returnType;
  FieldDecl[] arguments;
  this(Type type, Token identifier, Type returnType, FieldDecl[] args, Stmt funcBody) {
    super(type);
    this.identifier = identifier;
    this.returnType = type;
    this.arguments = args;
    this.fields = fields;
  }
}*/

class VarDecl : Decl {
  mixin NodeMixin;

  Expr typeExpr;

  this(Type type, Token name) {
    super(type, name);
  }
  this(Expr typeExpr, Token identifier) {
    super(null, identifier);
    this.typeExpr = typeExpr;
  }
}

class TypeDecl : Decl {
  mixin NodeMixin;

  this(Type type, Token name) {
    super(type, name);
  }
}

class ConstDecl : Decl {
  mixin NodeMixin;
  Expr value;

  this(Type type, Token name, Expr value) {
    super(type, name);
    this.value = value;
  }
}

class Stmts : Stmt {
  mixin NodeMixin;
  Stmt[] stmts;

  this (Stmt[] stmts) {
    this.stmts = stmts;
  }
};

class ImportStmt : Stmt {
  mixin NodeMixin;
  Token identifier;

  this(Token identifier) {
    this.identifier = identifier;
  }
}

class VarDeclStmt : Stmt {
  mixin NodeMixin;

  Token identifier;
  Decl decl;
  Expr expr;

  this(Token token, Decl decl, Expr expr) {
    this.identifier = token;
    this.decl = decl;
    this.expr = expr;
  }
}

class TypeDeclStmt : Stmt {
  mixin NodeMixin;

  Decl decl;

  this(Decl decl) {
    this.decl = decl;
  }
}


class ScopeStmt : Stmt {
  mixin NodeMixin;

  Stmts stmts;
  this(Stmts stmts) {
    this.stmts = stmts;
  }
}

abstract class Expr : Node {
  Type _exprType;

  @property bool exprTypeSet() {
    return _exprType !is null;
  }

  @property Type exprType() {
    if (!_exprType) {
      throw __ICE("Trying to use expression type before it is calculated");
    }
    return _exprType;
  }

  @property void exprType(Type type) {
    _exprType = type;
  }

  override string toString() {
    import duck.compiler.dbg;
    import duck.compiler.visitors;
    return cast(string)this.accept(ExprToString());
  }
}

class ErrorExpr : Expr {
    mixin NodeMixin;
    Slice slice;
    this(Slice span) {
      this.slice = slice;
      this.exprType = ErrorType.create;
    }
}

class ExprStmt : Stmt {
  mixin NodeMixin;

  Expr expr;
  this(Expr expr) {
    this.expr = expr;
  }
}

class InlineDeclExpr : IdentifierExpr {
  mixin NodeMixin;

  VarDeclStmt declStmt;

  this(Token token, VarDeclStmt declStmt) {
    super(token);
    this.declStmt = declStmt;
  }
}

class RefExpr : Expr {
  mixin NodeMixin;

  Decl decl;
  Token identifier;

  this(Token identifier, Decl decl) {
    this.identifier = identifier;
    this.decl = decl;
  }
}

class TypeExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TypeDecl decl;

  this(Expr expr) {
    this.expr = expr;
  }
}

class LiteralExpr : Expr {
  mixin NodeMixin;

  Token token;
  this(Token token) {
    this.token = token;
    if (token.type == Number)
      this.exprType = NumberType.create;
    else if (token.type == StringLiteral)
      this.exprType = StringType.create;
  }
}

class ArrayLiteralExpr : Expr {
  mixin NodeMixin;

  Expr[] exprs;
  this(Expr[] exprs) {
    this.exprs = exprs;
  }
}

class TupleExpr : Expr {
  mixin NodeMixin;

  Expr[] elements;

  this(Expr[] elements) {
    this.elements = elements;
  }

  int opApply(int delegate(ref Expr) dg)
  {
    int result = 0;
    for (int i = 0; i < elements.length; i++)
    {
      result = dg(elements[i]);
      if (result)
        break;
    }
    return result;
  }

  ref Expr opIndex(size_t index) {
    return elements[index];
  }

  size_t length() {
    return elements.length;
  }
}

class IdentifierExpr : Expr {
  mixin NodeMixin;

  string identifier;
  Token token;

  this(string identifier) {
    this.token = None;
    this.identifier = identifier;
  }
  this(Token token) {
    this.identifier = token.value;
    this.token = token;
  }
}

class UnaryExpr : Expr {
  mixin NodeMixin;

  Token operator;
  Expr operand;

  this(Token op, Expr operand) {
    operator = op;
    this.operand = operand;
  }
}

class BinaryExpr : Expr {
  mixin NodeMixin;

  Token operator;
  Expr left, right;

  this(Token op, Expr left, Expr right) {
    this.operator = op;
    this.left = left;
    this.right = right;
  }
}

class PipeExpr : BinaryExpr {
  mixin NodeMixin;

  this(Token op, Expr left, Expr right) {
    super(op, left, right);
  }
}

class AssignExpr : BinaryExpr {
  mixin NodeMixin;

  this(Token op, Expr left, Expr right) {
    super(op, left, right);
  }
}

class MemberExpr : BinaryExpr {
  mixin NodeMixin;

  this(Expr expr, Token identifier) {
    super(None, expr, new IdentifierExpr(identifier));
  }

  this(Expr left, Expr right) {
    super(None, left, right);
  }

}

class CallExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TupleExpr arguments;

  this(Expr expr, TupleExpr arguments) {
    this.expr = expr;
    this.arguments = arguments;
  }
}
