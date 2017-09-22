module duck.compiler.ast;

import duck.compiler.lexer, duck.compiler.types, duck.compiler.semantic;
import duck.compiler.scopes;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.context;
import duck.compiler.visitors.source;
import duck.compiler.util;
public import duck.compiler.attr;

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
  CastExpr,

  ExprStmt,
  DeclStmt,
  ScopeStmt,
  ImportStmt,
  ReturnStmt,
  IfStmt,
  Stmts,

  OverloadSet,
  ParameterDecl,
  CallableDecl,
  VarDecl,
  TypeDecl,
  ArrayDecl,
  FieldDecl,
  StructDecl,
  ModuleDecl,

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
  this() {}

  NodeType nodeType();
  Slice source() { return this.findSource(); }

  override size_t toHash() @trusted { return cast(size_t)cast(void*)this; }
  override bool opEquals(Object other) {
      return this is other;
  }
};

abstract class Stmt : Node {
};

class Library : Decl {
  mixin NodeMixin;

  Stmts stmts;
  ImportScope imports;
  FileScope globals;

  Decl[] exports;
  Node[] declarations;

  this(Stmts stmts, Node[] decls) {
    super(Slice(""), null);
    this.declarations = decls;
    this.imports = new ImportScope();
    this.stmts = stmts;
    this.globals = new FileScope();
  }
}

abstract class Decl : Node {
  Slice name;
  Type type;
  DeclAttr attributes;

  auto ref storage() { return attributes.storage; }
  auto ref visibility() { return attributes.visibility; }

  RefExpr reference() {
      return new RefExpr(this);
  }

  this(Slice name, Type type) {
    this.type = type;
    this.name = name;
  }

  @property
  bool hasError() {
    return false;
  }
}

class OverloadSet : ValueDecl {
  mixin NodeMixin;

  CallableDecl[] decls;

  alias decls this;
  void add(CallableDecl decl) {
    decls ~= decl;
  }

  this(Slice name) {
    super(OverloadSetType.create(this), name);
  }
}

class FieldDecl : VarDecl {
  mixin NodeMixin;

  this(Expr typeExpr, Token identifier, Expr valueExpr, StructDecl parent) {
    super(cast(Type)null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = valueExpr;
    this.parentDecl = parent;
  }
}

class ParameterDecl : ValueDecl {
  mixin NodeMixin;

  TypeExpr typeExpr;

  this(TypeExpr type, Slice name) {
    super(null, name);
    this.typeExpr = type;
  }
}

class CallableDecl : ValueDecl {
  mixin NodeMixin;

  @property
  FunctionType type() { return cast(FunctionType)super.type; }
  @property
  void type(FunctionType type) { super.type = type; }

  union {
    uint flags;
    struct {
      import std.bitmanip;
      mixin(bitfields!(
          int,  "filler", 3,
          bool, "isConstructor", 1,
          bool, "isOperator", 1,
          bool, "isExternal", 1,
          bool, "isMethod", 1,
          bool, "isMacro", 1));
    }
  }

  Slice headerSource;

  @property bool isFunction() { return !isMethod; }


  Stmt callableBody;
  TypeExpr[] parameterTypes;

  ParameterList  parameters;
  StructDecl parentDecl;

  Expr returnExpr;

  CallExpr call(Expr[] arguments = []) {
    return this.reference().call(arguments);
  }

  CallExpr call(TupleExpr arguments) {
    return this.reference().call(arguments);
  }

  this() {
    super(null, Slice());
    this.parameters = new ParameterList();
  }

  this(Slice identifier) {
    super(null, identifier);
    this.parameters = new ParameterList();
  }

  this(Slice identifier, TypeExpr contextType, TypeExpr[] argTypes, Expr expansion, StructDecl parentDecl) {
    super(null, identifier);
    this.parameters = new ParameterList();
    this.parameterTypes = argTypes;
    this.returnExpr = expansion;
    this.parentDecl = parentDecl;
  }
}

class ArrayDecl : TypeDecl {
  mixin NodeMixin;

  TypeDecl elementDecl;
  Type elementType() { return elementDecl.declaredType; }

  this(TypeDecl elementDecl) {
    this.elementDecl = elementDecl;
    super(ArrayType.create(elementType), Token());
  }

  this(TypeDecl elementDecl, uint size) {
    this.elementDecl = elementDecl;
    super(StaticArrayType.create(elementType, size), Token());
  }
}

class StructDecl : TypeDecl {
  mixin NodeMixin;

  DeclTable members;
  Decl context;

  bool external;

  auto fields() { return members.fields; }
  auto constructors() { return members.constructors; }
  auto methods() { return members.methods; }
  auto macros() { return members.macros; }
  auto all() { return members.all; }

  this(Type type, Slice name, bool external) {
    super(type, name);
    this.members = new DeclTable();
    this.external = external;
  }

  this(Slice name, bool external) {
    auto type = StructType.create(name);
    type.decl = this;
    this(type, name, external);
  }
}

class ModuleDecl : StructDecl {
  mixin NodeMixin;

  this(Token name, bool external) {
    auto type = ModuleType.create(name);
    type.decl = this;
    super(type, name, external);
  }
}

abstract class ValueDecl : Decl {
  this(Type type, Slice name) {
    super(name, type);
  }

  @property
  final override bool hasError() {
    return (cast(ErrorType)type) !is null;
  }
}

class VarDecl : ValueDecl {
  mixin NodeMixin;

  bool external;
  Expr typeExpr;
  Expr valueExpr;
  StructDecl parentDecl;

  this(Type type, Slice name, Expr value = null) {
    super(type, name);
    this.valueExpr = value;
  }
  this(TypeExpr typeExpr, Slice identifier, Expr value = null) {
    super(null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = value;
  }
}

class TypeDecl : Decl {
  mixin NodeMixin;

  Type declaredType;

  @property
  override bool hasError() {
    return (cast(ErrorType)declaredType) !is null;
  }

  this(Type type, Slice name = Slice()) {
    super(name, MetaType.create(type));
    this.declaredType = type;
  }

  this(Type type, string name) {
    super(Slice(name), MetaType.create(type));
    this.declaredType = type;
  }
}

class Stmts : Stmt {
  mixin NodeMixin;
  Stmt[] stmts;

  this (Stmt[] stmts = []) {
    this.stmts = stmts;
  }
};

class ImportStmt : Stmt {
  mixin NodeMixin;

  Token identifier;
  Context targetContext;

  this(Token identifier, Context context = null) {
    this.identifier = identifier;
    this.targetContext = context;
  }
}

class DeclStmt: Stmt {
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
  Type _type;

  @property
  final Type type(string file = __FILE__, int line = __LINE__) {
    ASSERT(_type, "Trying to use expression type before it is calculated", line, file);
    return _type;
  }

  @property
  final void type(Type type) {
    _type = type;
  }

  override string toString() {
    import duck.compiler.dbg.conv;
    return .toString(this);
  }

  CallExpr call(Expr[] arguments = []) {
    return new CallExpr(this, arguments, this.source);
  }

  CallExpr call(TupleExpr arguments) {
    return new CallExpr(this, arguments, this.source);
  }

  MemberExpr member(Slice name) {
    return new MemberExpr(this, name, this.source + name);
  }

  MemberExpr member(string name) {
    return new MemberExpr(this, name, this.source);
  }

  @property
  final bool hasError() {
    return (cast(ErrorType)this._type) !is null;
  }

  @property
  final bool hasType() {
    return this._type !is null;
  }

  Slice source;
}

E withSource(E: Expr)(E expr, Expr source) {
  expr.source = source.source;
  return expr;
}

E withSource(E: Expr)(E expr, Slice source) {
  expr.source = source;
  return expr;
}

class ErrorExpr : Expr {
    mixin NodeMixin;
    this(Slice source) {
      this.source = source;
      this.type = ErrorType.create;
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

class IfStmt: Stmt {
  mixin NodeMixin;

  Expr condition;
  Stmt trueBody, falseBody;

  this(Expr condition, Stmt trueBody, Stmt falseBody) {
    this.condition = condition;
    this.trueBody = trueBody;
    this.falseBody = falseBody;
  }
}

class InlineDeclExpr : IdentifierExpr {
  mixin NodeMixin;

  DeclStmt declStmt;

  this(DeclStmt declStmt) {
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

  Slice value;

  this(Token token) {
    this.source = token;
    this.value = token;
    if (token.type == Number) {
      import std.string: indexOf;
      if (token.slice.indexOf(".") >= 0)
        this.type = FloatType.create;
      else
        this.type = IntegerType.create;
    }
    else if (token.type == StringLiteral)
      this.type = StringType.create;
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

  alias elements this;
}

class IdentifierExpr : Expr {
  mixin NodeMixin;

  Slice identifier;

  this(string identifier) {
    this.identifier = Slice(identifier);
    this.source = this.identifier;
  }

  this(Slice slice) {
    this.identifier = slice;
    this.source = this.identifier;
  }

  this(IdentifierExpr expr) {
    this.identifier = expr.identifier;
    this.source = this.identifier;
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

class CastExpr: Expr {
  mixin NodeMixin;
  Expr expr;
  ref Type sourceType() { return expr._type; }
  Type targetType;

  this(Expr expr, Type targetType) {
    this.source = expr.source;
    this.expr = expr;
    this.targetType = targetType;
  }
}

class CallExpr : Expr {
  mixin NodeMixin;

  Expr callable;
  TupleExpr arguments;

  this(Expr callable, TupleExpr arguments, Slice source = Slice()) {
    this.callable = callable;
    this.arguments = arguments;
    this.source = source;
  }

  this(Expr callable, Expr[] arguments,  Slice source = Slice()) {
    this(callable, new TupleExpr(arguments), source);
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

  this(Expr expr, TupleExpr arguments, Slice source = Slice()) {
    super(expr, arguments, source);
  }

  this(Expr callable, Expr[] arguments, Slice source = Slice()) {
    this(callable, new TupleExpr(arguments), source);
  }
}


N as(N : Node)(Node node) { return cast(N) node; }
T as(T : Type)(Type type) { return cast(T) type; }
D as(D : Decl)(Decl decl) { return cast(D) decl; }

import std.range.primitives;
auto as(N: Node, R)(R range) if (isInputRange!R && is(ElementType!R: Node)) {
  import std.algorithm.iteration;
  return range.map!(node => node.as!N);
}
