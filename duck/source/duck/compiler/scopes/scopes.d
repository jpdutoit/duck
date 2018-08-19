module duck.compiler.scopes.scopes;

import duck.compiler.ast;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.util;
import duck.compiler.visitors.dup;
import duck.compiler.lexer;
import duck.util.stack;
import std.algorithm.iteration : filter;
import std.algorithm.searching : find;

//import duck.compiler.semantic.helpers;

alias ScopeLookup = Lookup!(Decl[]);

abstract class Scope: LookupContext {
  Scope parent;

  ScopeLookup lookup(string identifier);
  void define(string identifier, Decl decl);

  final bool defines(string identifier) {
    return !lookup(identifier).empty;
  }

  final ReadOnlyScope readonly() {
    return new ReadOnlyScope(this);
  }
}

class ReadOnlyScope : Scope {
  Scope target;

  this(Scope target) {
    this.target = target;
  }

  final override ScopeLookup lookup(string identifier) {
    return target.lookup(identifier);
  }

  final Expr createMemberReference(Decl member) {
    return target.createMemberReference(member);
  }

  final override void define(string identifier, Decl decl) {
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

  final override ScopeLookup lookup(string identifier) {
    if (ParameterDecl *decl = identifier in symbols) {
      return ScopeLookup(this, [*decl]);
    }
    return ScopeLookup(this, []);
  }

  final Expr createMemberReference(Decl member) {
    return new RefExpr(member);
  }

  final override void define(string identifier, Decl decl) {
    auto param = decl.enforce!ParameterDecl;
    elements ~= param;
    symbols[identifier] = param;
  }

  alias elements this;
}

class ImportScope: BlockScope {
  this(DeclTable table) {
    super(table);
  }
}

class FileScope: BlockScope {
  this(DeclTable table) {
    super(table);
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

  final override void define(string identifier, Decl decl) {
    table.define(identifier, decl);
  }

  final override ScopeLookup lookup(string identifier) {
    return ScopeLookup(this, table.lookup(identifier));
  }

  final Expr createMemberReference(Decl member) {
    return new RefExpr(member);
  }
}

class StructScope : Scope {
  ParameterList context;
  DeclTable table;

  this(StructDecl structDecl) {
    this.context = structDecl.context;
    this.table = structDecl.members;
  }

  final override void define(string identifier, Decl decl) {
    table.define(identifier, decl);
  }

  final override ScopeLookup lookup(string identifier) {
    auto lookup = this.context.lookup(identifier);
    if (lookup.empty) {
      return ScopeLookup(this, table.lookup(identifier));
    }
    return lookup;
  }

  final Expr createMemberReference(Decl member) {
    if (!this.context.elements.find(member).empty) {
      return new RefExpr(member);
    } else {
      auto thisRef = this.context.lookup("this").resolve();
      return new RefExpr(member, thisRef);
    }
  }
}

class WithScope : Scope {
  Expr target;

  this(Expr context) {
    this.target = context;
  }

  final override void define(string identifier, Decl decl) {
  }

  final override ScopeLookup lookup(string identifier) {
    import duck.compiler.scopes.lookup: lookup;
    return lookup(this.target, identifier);
  }

  final Expr createMemberReference(Decl member) {
    return new RefExpr(member, target.dup);
  }
}


class DeclTable {
  Decl[][string] symbols;

  auto all() {
    import std.algorithm.iteration: joiner;
    return symbols.byValue().joiner;
  }

  final void define(Decl decl) {
    define(decl.name, decl);
  }

  final bool defines(string identifier) {
    return !this.lookup(identifier).empty;
  }

  final void define(string identifier, Decl decl) {
    Decl[]* existing = identifier in symbols;

    if (existing) {
      (*existing) ~= decl;
    } else {
      Decl[] d = [decl];
      symbols[identifier] = [decl];
    }

    //all ~= decl;
  }

  final Decl[] lookup(string identifier) {
    if (Decl[] *decl = identifier in symbols)
      return *decl;
    return [];
  }

// Helper accesssors
  @property auto filtered(D: Decl)() {
    return all.filter!((d) => cast(D)d !is null);
  }

  @property auto fields() { return filtered!VarDecl; }
  @property auto callables() { return filtered!CallableDecl; }
  @property auto constructors() { return callables.filter!(d => d.as!CallableDecl.isConstructor); }
}

struct ScopeChainRange {
  Scope front;
  final bool empty() pure nothrow @nogc @safe  { return front is null; }
  final void popFront() pure nothrow @nogc @safe  { front = front.parent; }
  auto save() { return this; }
}

class SymbolTable {
  Scope top;

  final void pushScope(Scope s) {
    s.parent = top;
    top = s;
  }

  final void popScope() { top = top.parent; }

  final void define(string identifier, Decl decl) {
    top.define(identifier, decl);
  }

  auto scopes() {
    return ScopeChainRange(top);
  }

  alias scopes this;
}
