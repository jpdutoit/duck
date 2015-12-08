module duck.compiler.scopes;

import duck.compiler.ast;
import duck.compiler;
import duck.compiler.dbg;

interface Scope {
  Decl lookup(string identifier);
  void define(string identifier, Decl decl);
  bool defines(string identifier);
}

class DeclTable : Scope {
  Decl[string] symbols;
  Decl[] symbolsInDefinitionOrder;

  void define(string identifier, Decl decl) {
    if (identifier in symbols) {
      throw __ICE("Cannot redefine " ~ identifier.idup);
    }
    symbols[identifier] = decl;
    symbolsInDefinitionOrder ~= decl;
  }

  bool defines(string identifier) {
    return (identifier in symbols) != null;
  }

  Decl lookup(string identifier) {
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

    void define(string identifier, Decl decl) {
      return scopes[$-1].define(identifier, decl);
    }

    bool defines(string identifier) {
      return scopes[$-1].defines(identifier);
    }

    Decl lookup(string identifier) {
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
}
