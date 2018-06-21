module duck.compiler.ast.attr;

import duck.compiler;

enum Visibility {
  public_ = 0,
  private_ = 1,
}

@property
Visibility visibility(Token token)  {
  switch (token.type) {
    case Tok!"@public": return Visibility.public_;
    case Tok!"@private": return Visibility.private_;
    default:
    throw __ICE("Cannot get visbility value for token: " ~ token);
  }
}

enum StorageClass {
  defaultStorage = 0,
  mutableStorage = 1,
  constStorage = 2,
  dynamicStorage = 3
}

@property
StorageClass storageClass(Token token) {
  switch (token.type) {
    case Tok!"@const": return StorageClass.constStorage;
    default:
    throw __ICE("Cannot get storage class value for token: " ~ token);
  }
}

enum MethodBinding {
  dynamicBinding = 0,
  staticBinding = 1
}

@property
MethodBinding methodBinding(Token token)  {
  switch (token.type) {
    case Tok!"@static": return MethodBinding.staticBinding;
    default:
    throw __ICE("Cannot get method binding value for token: " ~ token);
  }
}


struct DeclAttr {
  union {
    uint flags = 0;
    struct {
      import std.bitmanip;
      mixin(bitfields!(
        int,  "_filler", 2,
        StorageClass, "storage", 2,
        Visibility, "visibility", 2,
        MethodBinding, "binding", 1,
        bool, "external", 1));
    }
  }
}
