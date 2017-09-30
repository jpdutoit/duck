module duck.compiler.scopes;

import duck.compiler.ast;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.util;
import duck.compiler.visitors.dup;
import duck.compiler.lexer;
import duck.util.stack;
import std.algorithm.iteration;

interface Scope {
  RefExpr reference(Slice identifier);

  Decl lookup(string identifier);
  void define(string identifier, Decl decl);

  final bool defines(string identifier) {
    return lookup(identifier) !is null;
  }

  final ReadOnlyScope readonly() {
    return new ReadOnlyScope(this);

  }
}

class ReadOnlyScope : Scope {
  Scope parent;

  this(Scope parent) {
    this.parent = parent;
  }

  final RefExpr reference(Slice identifier) {
    return parent.reference(identifier);
  }
  final Decl lookup(string identifier) {
    return parent.lookup(identifier);
  }

  final void define(string identifier, Decl decl) {
    ASSERT(false, "Cannot define in read only scope.");
  }
}

class ParameterList : Scope {
  ParameterDecl[string] symbols;
  ParameterDecl[] elements;

  void add(ParameterDecl decl) {
    elements ~= decl;
    symbols[decl.name] = decl;
  }

  final RefExpr reference(Slice identifier) {
    if (auto decl = lookup(identifier)) {
      return decl.reference().withSource(identifier);
    }
    return null;
  }

  final ParameterDecl lookup(string identifier) {
    if (ParameterDecl *decl = identifier in symbols) {
      return *decl;
    }
    return null;
  }

  final void define(string identifier, Decl decl) {
    auto param = cast(ParameterDecl)decl;
    elements ~= param;
    symbols[identifier] = param;
  }

  mixin ArrayWrapper!(ParameterDecl, elements);
}

class ImportScope: BlockScope {
  this() {
    super(new DeclTable);
  }
}

class FileScope: BlockScope {
  this() {
    super(new DeclTable);
  }
}

class BlockScope : Scope {
  DeclTable table;

  this(DeclTable table) {
    this.table = table;
  }

  this() {
    this.table = new DeclTable();
  }

  final void define(string identifier, Decl decl) {
    table.define(identifier, decl);
  }

  final Decl lookup(string identifier) {
    return table.lookup(identifier);
  }

  final RefExpr reference(Slice identifier) {
    return table.reference(identifier);
  }
}

class ThisScope : Scope {
  ValueDecl thisDecl;
  DeclTable table;

  this(StructDecl structDecl) {
    this.thisDecl = structDecl.context;
    this.table = structDecl.members;
  }

  this(ValueDecl thisDecl, DeclTable table) {
    this.thisDecl = thisDecl;
    this.table = table;
  }

  final void define(string identifier, Decl decl) {
    table.define(identifier, decl);
  }

  final Decl lookup(string identifier) {
    if ("this" == identifier) {
      return thisDecl;
    }
    return table.lookup(identifier);
  }

  final RefExpr reference(Slice identifier) {
    if ("this" == identifier) {
      return thisDecl.reference().withSource(identifier);
    }
    return table.reference(identifier, thisDecl.reference());
  }
}

class WithScope : Scope {
  Expr context;
  DeclTable table;

  this(Expr context, DeclTable table) {
    this.context = context;
    this.table = table;
  }

  final void define(string identifier, Decl decl) {
    table.define(identifier, decl);
  }

  final Decl lookup(string identifier) {
    return table.lookup(identifier);
  }

  final RefExpr reference(Slice identifier) {
    return table.reference(identifier, context.dup());
  }
}


class DeclTable {
  Decl[string] symbols;
  Decl[] all;

  final void replace(string identifier, Decl decl) {
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

  final void define(Decl decl) {
    define(decl.name, decl);
  }

  final void define(string identifier, Decl decl) {
    Decl* existing = identifier in symbols;

    if (existing) {
      if (auto cd = cast(CallableDecl)decl) {
        if (auto os = cast(OverloadSet)(*existing)) {
          os.add(cd);
          all ~= decl;
          return;
        }
      }
      ASSERT(false, "Cannot redefine " ~ identifier.idup);
    }

    all ~= decl;
    if (auto cd = cast(CallableDecl)decl) {
      OverloadSet os = new OverloadSet(decl.name);
      os.add(cd);
      decl = os;
    }
    symbols[identifier] = decl;
  }

  final Decl lookup(string identifier) {
    if (Decl *decl = identifier in symbols)
      return *decl;
    return null;
  }

  final RefExpr reference(Slice identifier, lazy Expr context = null) {
    if (auto decl = lookup(identifier)) {
      return decl.reference(context).withSource(identifier);
    }
    return null;
  }

  // Helper accesssors
  @property auto filtered(D: Decl)() {
    return all.filter!((d) => cast(D)d !is null);
  }

  @property auto fields() { return filtered!FieldDecl; }
  @property auto callables() { return filtered!CallableDecl; }
  @property auto macros() { return callables.filter!(d => d.as!CallableDecl.isMacro); }
  @property auto methods() { return callables.filter!(d => d.as!CallableDecl.isMethod); }
  @property auto constructors() { return callables.filter!(d => d.as!CallableDecl.isConstructor); }
}

class SymbolTable: Scope {
  Stack!Scope scopes;

  void pushScope(Scope s) { scopes.push(s); }
  void popScope() { scopes.pop(); }
  auto top() { return scopes.top; }

  final RefExpr reference(Slice identifier) {
    for (int i = cast(int)scopes.length - 1; i >= 0; --i) {
      if (auto refExpr = scopes[i].reference(identifier)) {
        return refExpr.withSource(identifier);
      }
    }
    return null;
  }

  final Decl lookup(string identifier) {
    debug(Scope) log("Looking for identifier '" ~ identifier ~ "'");
    for (int i = cast(int)scopes.length - 1; i >= 0; --i) {
      debug(Scope) log("  in", scopes[i]);
      if (auto decl = scopes[i].lookup(identifier)) {
        return decl;
      }
    }
    return null;
  }

  final void define(string identifier, Decl decl) {
    scopes.top.define(identifier, decl);
  }
}
