module duck.compiler.ast.decl;

import duck.compiler;

abstract class Decl : Node {
  Slice name;
  Type type;
  DeclAttr attributes;
  TypeDecl parent;

  auto ref storage() { return attributes.storage; }
  auto ref visibility() { return attributes.visibility; }
  auto ref isExternal() { return attributes.external; }

  RefExpr reference(Expr context = null) {
      return new RefExpr(this, context);
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

  BuiltinVarDecl arraySizeDecl;

  Decl[] exports;

  this(BlockStmt stmts) {
    super(Slice(""), null);
    this.imports = new ImportScope();
    this.stmts = stmts;
    this.globals = new FileScope();
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

class FieldDecl : VarDecl {
  mixin NodeMixin;

  final StructDecl parent() { return super.parent.enforce!StructDecl; }
  final void parent(StructDecl parent) { super.parent = parent; }

  this(Expr typeExpr, Token identifier, Expr valueExpr, StructDecl parent) {
    super(cast(Type)null, identifier);
    this.typeExpr = typeExpr;
    this.valueExpr = valueExpr;
    this.parent = parent;
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

class OverloadSet : ValueDecl {
  mixin NodeMixin;

  CallableDecl[] decls;

  alias decls this;
  final void add(CallableDecl decl) {
    decls ~= decl;
  }

  this(Slice name) {
    super(OverloadSetType.create(this), name);
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

  ParameterList  parameters;

  Expr returnExpr;

  final CallExpr call(Expr[] arguments = []) {
    return this.reference().call(arguments);
  }

  final CallExpr call(TupleExpr arguments) {
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

  this(Slice identifier, Expr expansion, StructDecl parentDecl) {
    super(null, identifier);
    this.parameters = new ParameterList();
    this.returnExpr = expansion;
    this.parent = parentDecl;
  }
}



class TypeDecl : Decl {
  mixin NodeMixin;

  final Type declaredType() { return this.type.as!MetaType.type; }

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

  this(Type elementType, uint size) {
    this.elementType = elementType;
    super(StaticArrayType.create(elementType, size), Token());
  }
}

class StructDecl : TypeDecl {
  mixin NodeMixin;

  DeclTable members;
  DeclTable publicMembers;
  ValueDecl context;

  final auto fields() { return members.fields; }
  final auto constructors() { return members.constructors; }
  final auto methods() { return members.methods; }
  final auto macros() { return members.macros; }
  final auto all() { return members.all; }

  this(Type type, Slice name) {
    super(type, name);
    this.members = new DeclTable();
    this.publicMembers = new DeclTable();
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
