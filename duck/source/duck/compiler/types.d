module duck.compiler.types;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;
private import std.conv;

alias BasicTypes = AliasSeq!("number", "string", "nothing", "error");
alias ExtendedTypes = AliasSeq!(StructType, ModuleType, FunctionType, ArrayType, TupleType, OverloadSetType, StaticArrayType, TypeType);

alias Types = AliasSeq!(NumberType, StringType, TypeType, VoidType, ErrorType, StructType, ModuleType, FunctionType, ArrayType, OverloadSetType, StaticArrayType);

template TypeId(T) {
  static if (staticIndexOf!(T, ExtendedTypes) >= 0) {
    enum TypeId = staticIndexOf!(T, ExtendedTypes) + BasicTypes.length;
  } else {
    static assert(0, T.stringof ~ " is not in extended types list.");
  }
}

template BasicType(string desc) {
  final class BasicType : Type {
    static enum _Kind Kind = staticIndexOf!(desc, BasicTypes);
    override _Kind kind() { return Kind; };
    static assert(Kind >= 0, T.stringof ~ " is not in basic types list.");

    static BasicType create() {
      return instance;
    }

    override string describe() const {
      return desc;
    }
    override bool opEquals(Object o) {
      return this is o;
    }
    private: static __gshared instance = new BasicType();
  }
  //static __gshared BasicType = new BasicTypeT();
}

alias NumberType = BasicType!("number");
alias StringType = BasicType!("string");
alias VoidType = BasicType!("nothing");
alias ErrorType = BasicType!("error");


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
  string describe() const ;

  final bool isKindOf(T)() {
    return this.kind == T.Kind;
  }

  bool isSameType(Type other) {
    return (this is other);
  }
};

final class TupleType : Type {
  mixin TypeMixin;

  Type[] elementTypes;

  override string describe() const {
    import std.conv : to;
    string s = "(";
    foreach (i, e ; elementTypes) {
      if (i != 0) s ~= ", ";
      s ~= e.describe();
    }
    return s ~ ")";
  }

  static auto create(Type[] elementTypes) {
    return new TupleType().init(elementTypes);
  }

  auto init(Type[] elementTypes) {
    this.elementTypes = elementTypes;
    return this;
  }

  size_t length() { return elementTypes.length; }
  ref Type opIndex(size_t index) { return elementTypes[index]; }
}

class StructType : Type {
  mixin TypeMixin;

  string name;
  StructDecl decl;

  override string describe() const {
    return cast(immutable)name;
  }

  static auto create(string name) {
    return new StructType().init(name);
  }

  auto init(string name) {
    this.name = name;
    return this;
  }
}

final class ArrayType : Type {
  mixin TypeMixin;

  Type elementType;

  override string describe() const {
    return elementType.describe() ~ "[]";
  }

  static auto create(Type elementType) {
    return new ArrayType().init(elementType);
  }

  override
  bool isSameType(Type other) {
    ArrayType a = cast(ArrayType)other;
    return a && a.elementType.isSameType((elementType));
  }

  auto init(Type elementType) {
    this.elementType = elementType;
    return this;
  }
}

final class StaticArrayType : Type {
  mixin TypeMixin;

  Type elementType;
  uint size;

  override string describe() const {
    return elementType.describe() ~ "[" ~ size.to!string ~ "]";
  }

  static auto create(Type elementType, uint size) {
    return new StaticArrayType().init(elementType, size);
  }

  override
  bool isSameType(Type other) {
    ArrayType a = cast(ArrayType)other;
    return a && a.elementType.isSameType((elementType));
  }

  auto init(Type elementType, uint size) {
    this.elementType = elementType;
    this.size = size;
    return this;
  }
}


final class ModuleType : StructType {
  mixin TypeMixin;

  override string describe() const {
    return "module." ~ name;
  }

  static ModuleType create(string name) {
    return new ModuleType().init(name);
  }

  ModuleType init(string name) {
    this.name = name;
    return this;
  }

}

class TypeType : Type {
  mixin TypeMixin;

  Type type;

  override string describe() const {
    return "Type";
  }

  static auto create(Type type) {
    return new TypeType().init(type);
  }

  override
  bool isSameType(Type other) {
    TypeType a = cast(TypeType)other;
    return a && a.type.isSameType(type);
  }

  auto init(Type type) {
    this.type = type;
    return this;
  }
}

class OverloadSetType : Type {
  mixin TypeMixin;

  static auto create(OverloadSet set) {
    auto o = new OverloadSetType();
    o.overloadSet = set;
    return o;
  }

  override string describe() const {
    return "overloads";
  }
  OverloadSet overloadSet;
}

class FunctionType : Type {
  mixin TypeMixin;

  static auto create(Type returnType, TupleType parameters) {
    auto f = new FunctionType();
    f.returnType = returnType;
    f.parameters = parameters;
    return f;
  }

  Type returnType;
  //Type[] parameterTypes;
  TupleType parameters;
  CallableDecl decl;

  override string describe() const {
    auto s = "ƒ(";
    foreach (i, param ; parameters.elementTypes) {
      if (i != 0) s ~= ", ";
      s ~= param.describe();
    }
    return s ~ ") -> "~returnType.describe;
  }
};

string mangled(const Type type) {
  return type ? type.describe() : "?";
}
