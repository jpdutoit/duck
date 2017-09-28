module duck.compiler.ast.decl;

import duck.compiler;

abstract class Decl : Node {
  Slice name;
  Type type;
  DeclAttr attributes;

  auto ref storage() { return attributes.storage; }
  auto ref visibility() { return attributes.visibility; }
  auto ref isExternal() { return attributes.external; }

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

class Library : Decl {
  mixin NodeMixin;

  BlockStmt stmts;
  ImportScope imports;
  FileScope globals;

  Decl[] exports;

  this(BlockStmt stmts) {
    super(Slice(""), null);
    this.imports = new ImportScope();
    this.stmts = stmts;
    this.globals = new FileScope();
  }

  static Library builtins() {
    BlockStmt stmts = new BlockStmt();
    stmts.append(new DeclStmt(new BasicTypeDecl(IntegerType.create, "int")));
    stmts.append(new DeclStmt(new BasicTypeDecl(FloatType.create, "float")));
    stmts.append(new DeclStmt(new BasicTypeDecl(BoolType.create, "bool")));
    stmts.append(new DeclStmt(new BasicTypeDecl(FloatType.create, "mono")));
    stmts.append(new DeclStmt(new BasicTypeDecl(StringType.create, "string")));
    return new Library(stmts);
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
          int,  "filler", 4,
          bool, "isConstructor", 1,
          bool, "isOperator", 1,
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

  this(Slice identifier, TypeExpr[] argTypes, Expr expansion, StructDecl parentDecl) {
    super(null, identifier);
    this.parameters = new ParameterList();
    this.parameterTypes = argTypes;
    this.returnExpr = expansion;
    this.parentDecl = parentDecl;
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

class BasicTypeDecl : TypeDecl {
  mixin NodeMixin;

  this(Type type, string name) {
    super(type, name);
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

  DeclTable members;
  Decl context;

  auto fields() { return members.fields; }
  auto constructors() { return members.constructors; }
  auto methods() { return members.methods; }
  auto macros() { return members.macros; }
  auto all() { return members.all; }

  this(Type type, Slice name) {
    super(type, name);
    this.members = new DeclTable();
  }

  this(Slice name) {
    auto type = StructType.create(name);
    type.decl = this;
    this(type, name);
  }
}

class ModuleDecl : StructDecl {
  mixin NodeMixin;

  this(Slice name) {
    auto type = ModuleType.create(name);
    type.decl = this;
    super(type, name);
  }
}
