module duck.compiler.scopes;

import duck.compiler.ast;
import duck.compiler;
import duck.compiler.dbg;

import duck.compiler.lexer;

interface Scope {
  Decl lookup(string identifier);
  bool defines(string identifier);
}

interface DefinitionScope : Scope {
  void define(string identifier, Decl decl);
}

class DeclTable : DefinitionScope {
  Decl[string] symbols;
  Decl[] symbolsInDefinitionOrder;

  void replace(string identifier, Decl decl) {
    Decl* existing = identifier in symbols;
    if (existing) {
      if (auto cd = cast(CallableDecl)decl) {
        OverloadSet os = new OverloadSet(decl.name);
        os.add(cd);
        decl = os;
      }
      symbols[identifier] = decl;
    }
  }

  void define(string identifier, Decl decl) {
    Decl* existing = identifier in symbols;

    if (existing) {
      if (auto cd = cast(CallableDecl)decl) {
        if (auto os = cast(OverloadSet)(*existing)) {
          os.add(cd);
          symbolsInDefinitionOrder ~= decl;
          return;
        }
      }
      else
        ASSERT(false, "Cannot redefine " ~ identifier.idup);
    }

    symbolsInDefinitionOrder ~= decl;
    if (auto cd = cast(CallableDecl)decl) {
      OverloadSet os = new OverloadSet(decl.name);
      os.add(cd);
      decl = os;
    }
    symbols[identifier] = decl;
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

    Scope top() {
        return scopes[$-1];
    }

    bool define(string identifier, Decl decl) {
      auto dscope = cast(DefinitionScope)top;
      if (dscope) {
        dscope.define(identifier, decl);
        return true;
      }
      return false;
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
