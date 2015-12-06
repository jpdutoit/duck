module duck.compiler.scopes;

import duck.compiler.ast;
import duck.compiler;

alias String = const(char)[];

interface Scope {
  Decl lookup(String identifier);
  void define(String identifier, Decl decl);
  bool defines(String identifier);
}

class DeclTable : Scope {
  Decl[String] symbols;
  Decl[] symbolsInDefinitionOrder;

  void define(String identifier, Decl decl) {
    if (identifier in symbols) {
      throw __ICE("Cannot redefine " ~ identifier.idup);
    }
    symbols[identifier] = decl;
    symbolsInDefinitionOrder ~= decl;
  }

  bool defines(String identifier) {
    return (identifier in symbols) != null;
  }

  Decl lookup(String identifier) {
    if (Decl *decl = identifier in symbols) {
      return *decl;
    }
    return null;
  }
}

class SymbolTable : Scope {
    Scope[] scopes;

    this() {
      assumeSafeAppend(scopes);
    }

    void define(String identifier, Decl decl) {
      return scopes[$-1].define(identifier, decl);
    }

    bool defines(String identifier) {
      return scopes[$-1].defines(identifier);
    }

    Decl lookup(String identifier) {
      for (int i = cast(int)scopes.length - 1; i >= 0; --i) {
        if (Decl decl = scopes[i].lookup(identifier))
          return decl;
      }
      return null;
    }

    void pushScope(Scope s) {
      scopes ~= s;
    }

    void popScope() {
      scopes.length--;
    }

    /*void print() {
      foreach (String name, Decl decl; symbols) {
        if (cast(VarDecl)decl) {
          //debug(Semantic) writefln("var %s = %s ", name, mangled(decl.declType));
        } else {
          //debug(Semantic) writefln("type %s = %s %s", name, mangled(decl.declType), decl);
        }
      }
    }*/
}
