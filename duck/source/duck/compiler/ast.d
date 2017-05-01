module duck.compiler.ast;

import duck.compiler.lexer, duck.compiler.types, duck.compiler.semantic;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.context;
import duck.compiler.visitors.source;

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
  Slice source() { return this.findSource(); }
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

  Slice name;

  Type declType;

  RefExpr reference() {
      return new RefExpr(this);
  }

  this(Type type, Slice name) {
    this.name = name;
    this.declType = type;
  }

  this(Slice name) {
    this.name = name;
  }
}

class UnboundDecl : Decl {
  mixin NodeMixin;

  this(Type type, string name) {
    super(type, Slice(name));
  }

  this(Type type, Slice name) {
    super(type, name);
  }
}

class OverloadSet : Decl {
  mixin NodeMixin;

  CallableDecl[] decls;

  void add(CallableDecl decl) {
    decls ~= decl;
  }

  this(Slice name) {
    super(OverloadSetType.create(this), name);
  }
}

class AliasDecl : Decl {
  mixin NodeMixin;

  Expr targetExpr;

  this(Slice identifier, Expr targetExpr) {
    super(null, identifier);
    this.targetExpr = targetExpr;
  }

  this(string identifier, Expr targetExpr) {
    this(Slice(identifier), targetExpr);
  }
}

class MacroDecl : CallableDecl {
  mixin NodeMixin;

  Expr expansion;
  alias argTypes = parameterTypes;
  alias argNames = parameterIdentifiers;
  StructDecl parentDecl;

  this(Slice identifier, TypeExpr contextType, TypeExpr[] argTypes, string[] argNames, Expr expansion, StructDecl parentDecl) {
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

/*class ParameterDecl : Decl {
  this(Slice name, Expr type) {
  }
}*/

class CallableDecl : Decl {
  Stmt callableBody;
  TypeExpr contextType;
  TypeExpr[] parameterTypes;
  string[] parameterIdentifiers;
  Expr returnExpr;
  bool external;
  bool dynamic;
  bool operator;

  CallExpr call(Expr[] arguments = []) {
    return this.reference().call(arguments);
  }

  this(Slice identifier) {
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

  this(Type type, Slice name) {
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

  this(Type type, Slice name) {
    super(type, name);
  }
  this(TypeExpr typeExpr, Slice identifier) {
    super(null, identifier);
    this.typeExpr = typeExpr;
  }
}

class TypeDecl : Decl {
  mixin NodeMixin;

  this(Type type, Slice name = Slice()) {
    super(type, name);
  }

  this(Type type, string name) {
    super(type, Slice(name));
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

  Decl decl;
  Expr expr;

  this(VarDecl decl, Expr expr) {
    this.decl = decl;
    this.expr = expr;
  }
}

class TypeDeclStmt : Stmt {
  mixin NodeMixin;

  Slice identifier;
  Decl decl;

  this(Slice identifier, Decl decl) {
    this.identifier = identifier;
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

  CallExpr call(Expr[] arguments = []) {
    return new CallExpr(this, arguments, null, this.source);
  }

  MemberExpr member(Slice name) {
    return new MemberExpr(this, name, this.source + name);
  }

  MemberExpr member(string name) {
    return new MemberExpr(this, name, this.source);
  }

  Expr withSource(Slice source) {
    this.source = source;
    return this;
  }

  Expr withSource(Expr expr) {
    this.source = expr.source;
    return this;
  }

  Slice source;
}

class ErrorExpr : Expr {
    mixin NodeMixin;
    this(Slice source) {
      this.source = source;
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

  this(VarDeclStmt declStmt) {
    super(declStmt.decl.name);
    this.declStmt = declStmt;
  }
}

class RefExpr : Expr {
  mixin NodeMixin;

  Decl decl;
  Expr context;

  this(Decl decl, Expr context = null, Slice source = Slice()) {
    this.decl = decl;
    this.context = context;
    this.source = source;
  }

  RefExpr withContext(Expr context) {
    this.context = context;
    return this;
  }
}

class TypeExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TypeDecl decl;

  this(Expr expr) {
    this.expr = expr;
    this.source = expr.source;
  }
}

class LiteralExpr : Expr {
  mixin NodeMixin;

  alias value = source;

  this(Token token) {
    super();
    this.source = token;
    if (token.type == Number)
      this.exprType = NumberType.create;
    else if (token.type == StringLiteral)
      this.exprType = StringType.create;
  }
}

class ArrayLiteralExpr : Expr {
  mixin NodeMixin;

  Expr[] exprs;
  this(Expr[] exprs, Slice source = Slice()) {
    this.exprs = exprs;
    this.source = source;
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

  alias identifier = source;

  this(string identifier) {
    this.identifier = Slice(identifier);
  }

  this(Slice slice) {
    this.identifier = slice;
  }

  this(IdentifierExpr expr) {
    this.identifier = expr.identifier;
  }
}

class UnaryExpr : Expr {
  mixin NodeMixin;

  Slice operator;
  union {
    Expr operand;
    Expr[1] arguments;
  }

  this(Slice op, Expr operand, Slice source = Slice()) {
    operator = op;
    this.operand = operand;
    this.source = source;
  }
}

class BinaryExpr : Expr {
  mixin NodeMixin;

  Slice operator;
  union {
    struct {
      Expr left, right;
    }
    Expr[2] arguments;
  }

  this(Slice op, Expr left, Expr right, Slice source = Slice()) {
    this.operator = op;
    this.left = left;
    this.right = right;
    this.source = source;
  }
}

class PipeExpr : BinaryExpr {
  mixin NodeMixin;

  this(Slice op, Expr left, Expr right) {
    super(op, left, right);
  }
}

class AssignExpr : BinaryExpr {
  mixin NodeMixin;

  this(Slice op, Expr left, Expr right) {
    super(op, left, right);
  }
}

class MemberExpr : Expr {
  mixin NodeMixin;

  Expr context;
  Slice name;

  this(Expr context, string member, Slice source) {
    this(context, Slice(member), source);
  }

  this(Expr context, Slice member, Slice source) {
    this.context = context;
    this.name = member;
    this.source = source;
  }

}

class CallExpr : Expr {
  mixin NodeMixin;

  Expr callable;
  TupleExpr arguments;
  Expr context;

  this(Expr callable, TupleExpr arguments, Expr context = null, Slice source = Slice()) {
    this.callable = callable;
    this.arguments = arguments;
    this.context = context;
    this.source = source;
  }

  this(Expr callable, Expr[] arguments, Expr context = null, Slice source = Slice()) {
    this(callable, new TupleExpr(arguments), context, source);
  }
}

class IndexExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TupleExpr arguments;

  this(Expr expr, TupleExpr arguments, Slice source = Slice()) {
    this.expr = expr;
    this.arguments = arguments;
    this.source = source;
  }
}


class ConstructExpr : CallExpr {
  mixin NodeMixin;

  alias target = callable;
  this(Expr expr, TupleExpr arguments, Slice source = Slice()) {
    super(expr, arguments, null, source);
  }
}
