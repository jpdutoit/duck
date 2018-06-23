module duck.compiler.types;

import duck.compiler;

import std.algorithm.iteration : map;
private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;
private import std.conv;
private import std.range, std.range.primitives;
private import std.array;
private import std.traits: Unqual;

alias BasicTypes = AliasSeq!("string", "nothing", "error", "float", "int", "bool");
alias ExtendedTypes = AliasSeq!(StructType, ModuleType, PropertyType, FunctionType, ArrayType, MacroType, TupleType, StaticArrayType, MetaType, UnresolvedType, DistinctType);

alias Types = AliasSeq!(FloatType, IntegerType, BoolType, StringType, MetaType, VoidType, ErrorType, StructType, ModuleType, PropertyType, FunctionType, MacroType, TupleType, ArrayType, StaticArrayType, UnresolvedType, DistinctType);

template TypeId(T) {
  static if (staticIndexOf!(T, ExtendedTypes) >= 0) {
    enum TypeId = staticIndexOf!(T, ExtendedTypes) + BasicTypes.length;
  } else {
    static assert(0, T.stringof ~ " is not in extended types list.");
  }
}

abstract class BasicType : Type { }

template ABasicType(string desc) {
  final class ABasicType : BasicType {
    static enum _Kind Kind = staticIndexOf!(desc, BasicTypes);
    override _Kind kind() { return Kind; };
    static assert(Kind >= 0, T.stringof ~ " is not in basic types list.");

    static ABasicType create() {
      return instance;
    }

    override string describe() const {
      return desc;
    }
    override bool opEquals(Object o) {
      return this is o;
    }
    private: static __gshared instance = new ABasicType();
  }
  //static __gshared BasicType = new BasicTypeT();
}

alias FloatType = ABasicType!("float");
alias IntegerType = ABasicType!("int");
alias BoolType = ABasicType!("bool");
alias StringType = ABasicType!("string");
alias VoidType = ABasicType!("nothing");
alias ErrorType = ABasicType!("error");


mixin template TypeMixin() {
  static enum Kind = TypeId!(typeof(this));//;staticIndexOf!(typeof(this), Types);
  static if (Kind < 0) {
    static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in Types list.");
  }
  override _Kind kind() { return Kind; };
};


abstract class Type {
  alias _Kind = ubyte;

  _Kind kind();
  string describe() const;

  bool isSameType(Type other) {
    return (this is other);
  }

  @property
  final bool hasError() {
    return cast(ErrorType)this !is null;
  }
}

final class TupleType : Type {
  mixin TypeMixin;

  Type[] elementTypes;

  override string describe() const {
    return "(" ~ elementTypes.describe(",") ~ ")";
  }


  static auto create(Type[] elementTypes) {
    auto t = new TupleType();
    t.elementTypes = elementTypes;
  	return t;
  }

  alias elementTypes this;
}

class DistinctType: Type {
  mixin TypeMixin;

  string name;
  Type baseType;

  string debugDescription() const {
    return "(" ~ this.name ~ ": distinct " ~ this.baseType.describe() ~ ")";
  }

  override string describe() const {
    return this.name;
  }

  static auto create(string name, Type baseType) {
    auto t = new DistinctType();
    t.name = name;
    t.baseType = baseType;
    return t;
  }
}

class StructType : Type {
  mixin TypeMixin;

  string name;
  StructDecl decl;
  auto members() { return decl.members; }

  this(string name) {
    this.name = name;
  }

  override string describe() const {
    return cast(immutable)name;
  }

  static auto create(string name) {
    return new StructType(name);
  }
}

final class ArrayType : Type {
  mixin TypeMixin;

  Type elementType;

  override string describe() const {
    return elementType.describe() ~ "[]";
  }

  static auto create(Type elementType) {
    return new ArrayType(elementType);
  }

  override
  bool isSameType(Type other) {
    ArrayType a = cast(ArrayType)other;
    return a && a.elementType.isSameType((elementType));
  }

  this(Type elementType) {
    this.elementType = elementType;
  }
}

final class StaticArrayType : Type {
  mixin TypeMixin;

  Type elementType;
  long size;

  override string describe() const {
    return elementType.describe() ~ "[" ~ size.to!string ~ "]";
  }

  static auto create(Type elementType, long size) {
    return new StaticArrayType(elementType, size);
  }

  override
  bool isSameType(Type other) {
    StaticArrayType a = cast(StaticArrayType)other;
    return a && a.size == this.size && a.elementType.isSameType((elementType));
  }

  this(Type elementType, long size) {
    this.elementType = elementType;
    this.size = size;
  }
}


final class ModuleType : StructType {
  mixin TypeMixin;

  ModuleDecl decl() { return cast(ModuleDecl)super.decl; }
  void decl(ModuleDecl decl) { super.decl = decl; }

  override string describe() const {
    return "Module_" ~ name;
  }

  static ModuleType create(string name) {
    return new ModuleType(name);
  }

  this(string name) {
    super(name);
  }

}


final class PropertyType : StructType {
  mixin TypeMixin;

  PropertyDecl decl() { return cast(PropertyDecl)super.decl; }
  void decl(PropertyDecl decl) { super.decl = decl; }

  override string describe() const {
    return "Property_" ~ name;
  }

  static PropertyType create(string name) {
    return new PropertyType(name);
  }

  this(string name) {
    super(name);
  }

}

class MetaType : Type {
  mixin TypeMixin;

  Type type;

  override string describe() const {
    return "Type(" ~ type.describe() ~ ")";
  }

  static auto create(Type type) {
    return new MetaType(type);
  }

  override
  bool isSameType(Type other) {
    MetaType a = cast(MetaType)other;
    return a && a.type.isSameType(type);
  }

  this(Type type) {
    this.type = type;
  }
}

class UnresolvedType: Type {
  mixin TypeMixin;

  Lookup!(Decl[]) lookup;

  static auto create(D)(Lookup!D lookup) {
    auto t = new UnresolvedType();
    t.lookup = lookup;
    return t;
  }

  override string describe() const {
    return "(" ~ lookup.decls.describe(" | ") ~ ")";
  }

  auto types() {
    return lookup.decls.map!(decl => decl.type);
  }
}

class FunctionType : Type {
  mixin TypeMixin;

  CallableDecl decl;

  static auto create(Type returnType, TupleType parameters, CallableDecl decl) {
    auto f = new FunctionType();
    f.returnType = returnType;
    f.parameterTypes = parameters;
    f.decl = decl;
    return f;
  }

  Type returnType;
  TupleType parameterTypes;

  override string describe() const {
    return "ƒ" ~ parameterTypes.describe ~ " -> " ~ returnType.describe;
  }
}

class MacroType: FunctionType {
  mixin TypeMixin;

  static auto create(Type returnType, TupleType parameters, CallableDecl decl) {
    auto f = new MacroType();
    f.returnType = returnType;
    f.parameterTypes = parameters;
    f.decl = decl;
    return f;
  }

  override string describe() const {
    return "macro" ~ parameterTypes.describe ~ " -> expr";
  }
}

string describe(R)(R r, string separator = ", ") if (isForwardRange!R && is(Unqual!(ElementType!R): Type)) {
  auto s = "";
  foreach (i, param ; r.save) {
    if (i != 0) s ~= separator;
    s ~= param.describe();
  }
  return s;
}

string describe(R)(R r, string separator = ", ") if (isInputRange!R && is(Unqual!(ElementType!R): Decl)) {
  auto s = "";
  foreach (i, param ; r.save) {
    if (i != 0) s ~= separator;
    s ~= param.type.describe();
  }
  return s;
}

string mangled(const Type type) {
  return type ? type.describe() : "?";
}
