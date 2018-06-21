module duck.compiler.ast.decl;

import duck.compiler;

abstract class Decl : Node {
  Slice name;
  Type type;

  Decl parent;
  DeclAttr attributes;

  bool semantic;

  auto ref storage() { return attributes.storage; }
  auto ref visibility() { return attributes.visibility; }
  auto ref isExternal() { return attributes.external; }

  RefExpr reference(Expr context) {
      return new RefExpr(this, context);
  }

  final Type declaredType() {
    if (auto metaType = this.type.as!MetaType) {
      return metaType.type;
    }
    return null;
  }

  override string toString() {
    import duck.compiler.dbg.conv: toString;
    return .toString(this);
  }

  this(Decl parent, DeclAttr attributes, Slice name = Slice()) {
    this.name = name;
    this.parent = parent;
    this.attributes = attributes;
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

class Library : TypeDecl {
  mixin NodeMixin;

  BlockStmt stmts;
  DeclTable imports;
  DeclTable globals;

  BuiltinVarDecl arraySizeDecl;

  Decl[] exports;

  this(BlockStmt stmts) {
    super(null, Slice(""));
    this.imports = new DeclTable();
    this.stmts = stmts;
    this.globals = new DeclTable();
    this.arraySizeDecl = new BuiltinVarDecl(IntegerType.create, "length");
  }

  static Library builtins() {
    BlockStmt stmts = new BlockStmt();
    stmts.append(new BasicTypeDecl(IntegerType.create, "int"));
    stmts.append(new BasicTypeDecl(FloatType.create, "float"));
    stmts.append(new BasicTypeDecl(BoolType.create, "bool"));
    stmts.append(new BasicTypeDecl(FloatType.create, "mono"));
    stmts.append(new BasicTypeDecl(StringType.create, "string"));
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

  this(Type type, Slice name, Expr value = null) {
    super(type, name);
    this.valueExpr = value;
  }
  this(Expr typeExpr, Slice identifier, Expr value = null) {
    super(null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = value;
  }
}

class BuiltinVarDecl : VarDecl {
  mixin NodeMixin;

  string name;

  this(Type type, string name) {
    this.name = name;
    super(type, Slice());
  }
}

class ParameterDecl : ValueDecl {
  mixin NodeMixin;

  Expr typeExpr;

  this(Expr type, Slice name) {
    super(null, name);
    this.typeExpr = type;
  }
}

class AliasDecl : ValueDecl {
  mixin NodeMixin;
  Expr value;

  this(Slice name, Expr value) {
    super(null, name);
    this.value = value;
  }
}

class CallableDecl : ValueDecl {
  mixin NodeMixin;

  @property
  final FunctionType type() { return cast(FunctionType)super.type; }
  @property
  final void type(FunctionType type) { super.type = type; }

  union {
    uint flags;
    struct {
      import std.bitmanip: bitfields;
      mixin(bitfields!(
          int,  "filler", 5,
          bool, "isConstructor", 1,
          bool, "isOperator", 1,
          bool, "isPropertyAccessor", 1));
    }
  }

  Slice headerSource;

  Stmt callableBody;

  ParameterList parameters;

  Expr returnExpr;

  this() {
    super(null, Slice());
    this.parameters = new ParameterList();
    //this.context = new ParameterList();
  }

  this(Slice identifier) {
    super(null, identifier);
    this.parameters = new ParameterList();
    //this.context = new ParameterList();
  }

  this(Slice identifier, Expr expansion, StructDecl parentDecl) {
    super(null, identifier);
    this.parameters = new ParameterList();
    //this.context = new ParameterList();
    this.returnExpr = expansion;
    this.parent = parentDecl;
  }
}

class TypeDecl : Decl {
  mixin NodeMixin;

  @property
  override bool hasError() {
    return (cast(ErrorType)declaredType) !is null;
  }

  this(Type type, Slice name = Slice()) {
    super(name, MetaType.create(type));
  }

  this(Type type, string name) {
    super(Slice(name), MetaType.create(type));
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

  this(Type elementType, long size) {
    this.elementType = elementType;
    super(StaticArrayType.create(elementType, size), Token());
  }
}

class StructDecl : TypeDecl {
  mixin NodeMixin;

  DeclTable members;
  ParameterList context;

  final auto fields() { return members.fields; }
  final auto constructors() { return members.constructors; }
  final auto all() { return members.all; }

  BlockStmt structBody;

  this(Type type, Slice name) {
    super(type, name);
    this.members = new DeclTable();
    this.context = new ParameterList();
    this.context.add(new ParameterDecl(this.reference(null), Slice("this")));
  }

  this(Slice name) {
    auto type = StructType.create(name);
    type.decl = this;
    this(type, name);
  }
}

class PropertyDecl: StructDecl {
  mixin NodeMixin;

  Expr typeExpr;

  this(Expr typeExpr, Slice identifier) {
    auto type = PropertyType.create(identifier);
    type.decl = this;
    super(type, identifier);
    this.typeExpr = typeExpr;
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
