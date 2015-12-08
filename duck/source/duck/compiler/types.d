module duck.compiler.types;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;

alias BasicTypes = AliasSeq!("number", "string", "type", "nothing", "error");
alias ExtendedTypes = AliasSeq!(StructType, GeneratorType, FunctionType, ArrayType);

template TypeId(T) {
  static if (staticIndexOf!(T, ExtendedTypes) >= 0) {
    enum TypeId = staticIndexOf!(T, ExtendedTypes) + BasicTypes.length;
  } else {
    static assert(0, T.stringof ~ " is not in extended types list.");
  }
}

template BasicType(string desc) {
  final class BasicTypeT : Type {
    static enum _Kind Kind = staticIndexOf!(desc, BasicTypes);
    override _Kind kind() { return Kind; };
    static assert(Kind >= 0, T.stringof ~ " is not in basic types list.");

    override string describe() const {
      return desc;
    }
    override bool opEquals(Object o) {
      return this is o;
    }
  }
  static __gshared BasicType = new BasicTypeT();
}

alias NumberType = BasicType!("number");
alias StringType = BasicType!("string");
alias TypeType = BasicType!("type");
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

};

final class StructType : Type {
  mixin TypeMixin;

  string name;

  override string describe() const {
    return cast(immutable)name;
  }

  this(string name) {
    this.name = name;
  }
}

final class ArrayType : Type {
  mixin TypeMixin;

  Type elementType;

  override string describe() const {
    return "array with elements of type " ~ elementType.describe;// ~ "[]";
  }

  this(Type elementType) {
    this.elementType = elementType;
  }
}


final class GeneratorType : Type {
  mixin TypeMixin;

  string name;
  StructDecl decl;

  override string describe() const {
    return cast(immutable)name;
  }
  this(string name) {
    this.name = name;
  }
}

class FunctionType : Type {
  mixin TypeMixin;

  this(Type returnType, Type[] parameterTypes) {
      this.returnType = returnType;
      this.parameterTypes = parameterTypes;
  }

  Type returnType;
  Type[] parameterTypes;
  override string describe() const {
    auto s = "ƒ(";
    foreach (i, param ; parameterTypes) {
      if (i != 0) s ~= ", ";
      s ~= param.describe();
    }
    return s ~ ")";// ~ ")->"~returnType.mangled;
  }
};

string mangled(const Type type) {
  return type ? type.describe() : "?";
}
