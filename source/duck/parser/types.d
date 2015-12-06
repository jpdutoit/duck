module duck.compiler.types;

import duck.compiler.ast, duck.compiler.lexer, duck.compiler.types;

private import std.meta : AliasSeq;
private import std.typetuple: staticIndexOf;

alias Types = AliasSeq!(NumberType, StringType, VoidType, FunctionType, StructType, GeneratorType, TypeType, ErrorType, ArrayType);

mixin template TypeMixin() {
  static enum Kind = staticIndexOf!(typeof(this), Types);
  static if (Kind < 0) {
    //#TODO:0 Do it right
    static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in Types list.");
  }
  override _Kind kind() { return Kind; };
};

bool isKindOf(T)(Type type) {
  return type.kind == T.Kind;
}


abstract class Type {
  alias _Kind = ubyte;

  _Kind kind();
  string mangled() const ;

  Decl decl;
};

final class NumberType : Type {
  mixin TypeMixin;
  override string mangled() const {
    return "number";
  }
}

final class StringType : Type {
  mixin TypeMixin;
  override string mangled() const  {
    return "string";
  }
}

final class TypeType : Type {
  mixin TypeMixin;
  override string mangled() const  {
    return "Type";
  }
}

final class VoidType : Type {
  mixin TypeMixin;
  override string mangled() const  {
    return "Void";
  }
}

class ErrorType : Type {
  mixin TypeMixin;
  override string mangled() const  {
    return "Error";
  }
}


final class StructType : Type {
  mixin TypeMixin;

  String name;

  override string mangled() const {
    return cast(immutable)name;// ~ ":Obj";
  }

  this(String name) {
    this.name = name;
  }
}

final class ArrayType : Type {
  mixin TypeMixin;

  Type elementType;

  override string mangled() const {
    return "array with elements of type " ~ elementType.mangled;// ~ "[]";
  }

  this(Type elementType) {
    this.elementType = elementType;
  }
}


final class GeneratorType : Type {
  mixin TypeMixin;

  String name;

  override string mangled() const {
    return cast(immutable)name;// ~ ":Gen";
  }
  this(String name) {
    this.name = name;
  }
}
/*
final class NamedType : Type {
  mixin TypeMixin;
  string name;
  Type realType;
  this(string name, Type type) {
    this.name = name;
    this.realType = type;
  }
  override string mangled() const {
    return name;
    //return "(" ~ name ~ ":" ~ this.realType.mangled ~ ")";
  }
}*/

class FunctionType : Type {
  mixin TypeMixin;

  this(Type returnType, Type[] parameterTypes) {
      this.returnType = returnType;
      this.parameterTypes = parameterTypes;
  }

  Type returnType;
  Type[] parameterTypes;
  override string mangled() const {
    auto s = "ƒ(";
    foreach (i, param ; parameterTypes) {
      if (i != 0) s ~= ", ";
      s ~= param.mangled();
    }
    return s ~ ")";// ~ ")->"~returnType.mangled;
  }
};


string mangled(const Type type) {
  return type ? type.mangled() : "?";
}

__gshared errorType = new ErrorType();
__gshared numberType = new NumberType();
__gshared stringType = new StringType();
__gshared typeType = new TypeType();
__gshared voidType = new VoidType();
