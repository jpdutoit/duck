module duck.compiler.scopes;

import duck.compiler.ast;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.util;

import duck.compiler.lexer;

interface Scope {
  Decl lookup(string identifier);
  bool defines(string identifier);

  final LookupScope readonly() {
    return new LookupScope(this);
  }
}

interface DefinitionScope : Scope {
  void define(Decl decl);
  void define(string identifier, Decl decl);
  bool defines(string identifier);
}

class LookupScope : Scope {
  Scope target;

  this(Scope target) {
    this.target = target;
  }

  Decl lookup(string identifier) {
    return target.lookup(identifier);
  }

  bool defines(string identifier) {
    return target.defines(identifier);
  }
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
    } else {
      define(identifier, decl);
    }
  }

  void define(Decl decl) {
    define(decl.name, decl);
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

class ParameterList : Scope {
  ParameterDecl[string] symbols;
  ParameterDecl[] elements;

  bool defines(string identifier) {
    return (identifier in symbols) != null;
  }

  void add(ParameterDecl decl) {
    elements ~= decl;
    symbols[decl.name] = decl;
  }

  ParameterDecl lookup(string identifier) {
    if (ParameterDecl *decl = identifier in symbols) {
      return *decl;
    }
    return null;
  }

  mixin ArrayWrapper!(ParameterDecl, elements);
}

struct ActiveScope {
    Scope theScope;
    Expr context;

    this(Scope theScope, Expr context) {
      this.theScope = theScope;
      this.context = context;
    }
    alias theScope this;
}


struct ContextDecl {
    Expr context;
    Decl decl;
    alias decl this;
    this(Expr context, Decl decl) {
      this.context = context;
      this.decl = decl;
    }

    bool opCast(T : bool)() const {
      return decl !is null;
    }
}

class SymbolTable {
    ActiveScope[] scopes;

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

    ContextDecl lookup(string identifier) {
      for (int i = cast(int)scopes.length - 1; i >= 0; --i) {
        if (Decl decl = scopes[i].lookup(identifier)) {
          return ContextDecl(scopes[i].context, decl);
        }
      }
      return ContextDecl(null, null);
    }

    void pushScope(Scope s, Expr context = null) {
      scopes ~= ActiveScope(s, context);
    }

    void popScope() {
      scopes.length--;
    }
}
