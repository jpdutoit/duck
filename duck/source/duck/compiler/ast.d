module duck.compiler.ast;

import duck.compiler.lexer, duck.compiler.types, duck.compiler.semantic;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.context;

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
  ConstructExpr,
  TupleExpr,
  IndexExpr,

  ExprStmt,
  VarDeclStmt,
  TypeDeclStmt,
  ScopeStmt,
  ImportStmt,
  ReturnStmt,
  Stmts,

  Decl,
  UnboundDecl,
  OverloadSet,
  FunctionDecl,
  VarDecl,
  TypeDecl,
  ArrayDecl,
  ConstDecl,
  FieldDecl,
  MethodDecl,
  StructDecl,
  ModuleDecl,
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

  Stmt[] nodes;
  DeclTable imports;
  Decl[] exports;
  Node[] declarations;

  this(Stmt[] stmts, Node[] decls) {
    this.declarations = decls;
    this.imports = new DeclTable();
    this.nodes = stmts;
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

class UnboundDecl : Decl {
  mixin NodeMixin;

  this(Type type, Token name) {
    super(type, name);
  }

  this(Token name) {
    super(name);
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
  StructDecl parentDecl;

  this(Token identifier, TypeExpr contextType, TypeExpr[] argTypes, Token[] argNames, Expr expansion, StructDecl parentDecl) {
    super(identifier);
    this.contextType = contextType;
    this.returnExpr = null;
    this.argTypes = argTypes;
    this.argNames = argNames;
    this.expansion = expansion;
    this.dynamic = parentDecl !is null;
    this.parentDecl = parentDecl;
  }
}

class FieldDecl : Decl {
  mixin NodeMixin;

  Expr typeExpr;
  alias identifier = name;
  Expr valueExpr;
  StructDecl parentDecl;

  this(Expr typeExpr, Token identifier, Expr valueExpr, StructDecl parent) {
    super(null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = valueExpr;
    this.parentDecl = parent;
  }
}

class CallableDecl : Decl {
  Stmt callableBody;
  TypeExpr contextType;
  TypeExpr[] parameterTypes;
  Token[] parameterIdentifiers;
  Expr returnExpr;
  bool external;
  bool dynamic;
  bool operator;

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
  StructDecl parentDecl;

  this(Token identifier) {
    super(identifier);
  }
}

class ArrayDecl : TypeDecl {
  mixin NodeMixin;

  Type elementType;

  this(Type elementType) {
    this.elementType = elementType;
    super(ArrayType.create(elementType), Token());
  }

  this(Type elementType, uint size) {
    this.elementType = elementType;
    super(StaticArrayType.create(elementType, size), Token());
  }
}

class StructDecl : TypeDecl {
  mixin NodeMixin;

  DeclTable decls;
  OverloadSet ctors;

  bool external;

  this(Type type, Token name) {
    ctors = new OverloadSet(name);
    super(type, name);
    decls = new DeclTable();
  }
}

class ModuleDecl : StructDecl {
  mixin NodeMixin;

  this(Type type, Token name) {
    super(type, name);
  }
}

class VarDecl : Decl {
  mixin NodeMixin;

  bool external;
  TypeExpr typeExpr;

  this(Type type, Token name) {
    super(type, name);
  }
  this(TypeExpr typeExpr, Token identifier) {
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
  Context targetContext;

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

  @property Type exprType(string file = __FILE__, int line = __LINE__) {
    ASSERT(_exprType, "Trying to use expression type before it is calculated", line, file);
    return _exprType;
  }

  @property void exprType(Type type) {
    _exprType = type;
  }

  override string toString() {
    import duck.compiler.dbg.conv;
    return .toString(this);
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

class ReturnStmt : Stmt {
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
  Expr context;

  this(Token identifier, Decl decl, Expr context = null) {
    this.identifier = identifier;
    this.decl = decl;
    this.context = context;
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

  this(Token token) {
    this.identifier = token.value;
    this.token = token;
  }
}

class UnaryExpr : Expr {
  mixin NodeMixin;

  Token operator;
  union {
    Expr operand;
    Expr[1] arguments;
  }

  this(Token op, Expr operand) {
    operator = op;
    this.operand = operand;
  }
}

class BinaryExpr : Expr {
  mixin NodeMixin;

  Token operator;
  union {
    struct {
      Expr left, right;
    }
    Expr[2] arguments;
  }

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

class MemberExpr : Expr {
  mixin NodeMixin;

  Expr context;
  Token member;

  this(Expr context, Token member) {
    this.context = context;
    this.member = member;
  }

}

class CallExpr : Expr {
  mixin NodeMixin;

  Expr callable;
  TupleExpr arguments;
  Expr context;

  this(Expr callable, TupleExpr arguments, Expr context = null) {
    this.callable = callable;
    this.arguments = arguments;
    this.context = context;
  }

  this(Expr callable, Expr[] arguments, Expr context = null) {
    this.callable = callable;
    this.arguments = new TupleExpr(arguments);
    this.context = context;
  }
}

class IndexExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TupleExpr arguments;

  this(Expr expr, TupleExpr arguments) {
    this.expr = expr;
    this.arguments = arguments;
  }
}


class ConstructExpr : CallExpr {
  mixin NodeMixin;

  alias target = callable;
  this(Expr expr, TupleExpr arguments) {
    super(expr, arguments);
  }
}
