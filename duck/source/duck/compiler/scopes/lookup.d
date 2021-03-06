module duck.compiler.scopes.lookup;

public import std.range.primitives;

import duck.compiler.ast;
import duck.compiler;
import duck.compiler.dbg;
import duck.compiler.util;
import duck.compiler.visitors.dup;
import duck.compiler.lexer;
import duck.compiler.scopes.scopes;
import duck.util.stack;

import duck.compiler.semantic.helpers;

import std.algorithm.iteration : filter, map;
import std.range.primitives;
import std.range;
import std.traits: ReturnType;

import std.functional: unaryFun;

template supportsLookup(T) {
  static if (is(ReturnType!((T t, Slice id) => t.lookup(id)) R)) {
    enum bool supportsLookup =
      isForwardRange!R
      && is(ElementType!R: Decl)
      && is(T: LookupContext)
      && is(ReturnType!((T t, Decl d) => t.createMemberReference(d)): Expr);
  } else {
    enum bool supportsLookup = false;
  }
}

interface LookupContext {
  Expr createMemberReference(Decl member);
}

static assert(supportsLookup!Expr);
static assert(supportsLookup!Scope);

static struct ResolvedLookup {
  LookupContext parent;
  Decl declaration;
  alias declaration this;

  bool opCast(T: bool)() const { return declaration !is null; }
  Expr reference() { return parent.createMemberReference(declaration); }
}

// Store the result of a namespace lookup as a context along with a range of declarations
struct Lookup(DeclRange) if (isForwardRange!DeclRange && is(ElementType!DeclRange: Decl)) {

  LookupContext parent;
  DeclRange decls;

  bool opCast(T: bool)() { return !decls.empty; }

  Lookup save() { return Lookup(parent, decls.save); }
  size_t count() { return decls.save.walkLength(); }

  Expr resolve(T = Expr)() {
    return decls.save.walkLength(2) == 1
      ? parent.createMemberReference(decls.front)
      : null;
  }

  Type resolve(T: Type)() {
    return decls.save.walkLength(2) == 1
      ? decls.front().type
      : null;
  }

  Type type()() {
    if (empty) return null;
    return decls.save.walkLength(2) == 1
    ? front().type
    : UnresolvedType.create(this);
  }

  Expr reference(Decl decl) {
    return parent.createMemberReference(decl);
  }

  alias decls this;
}

static auto _lookup(T)(LookupContext parent, T decls) {
  return Lookup!T(parent, decls);
}

auto filtered(alias predicate, T)(Lookup!T lookup)
  if (is(typeof(unaryFun!predicate)))
{
  return _lookup(lookup.parent, lookup.decls.filter!predicate);
}

// Returns a range of overload sets containing declarations with name `identifier`
auto stagedLookup(SymbolTable symbolTable, Slice identifier) {
  return symbolTable.scopes
    .map!(next => next.lookup(identifier))
    .filter!(a => !a.empty);
}

auto lookup(Type type, string identifier, Visibility vis = Visibility.public_) {
    Lookup!(Decl[]) lookup;

    if (auto metaType = type.as!MetaType) {
      if (auto structType = metaType.type.as!StructType) {
        return _lookup(
          null,
          vis == Visibility.public_
            ? structType.decl.members.lookup(identifier).filter!(d => d.visibility == Visibility.public_ && d.attributes.binding == MethodBinding.staticBinding).array
            : structType.decl.members.lookup(identifier).filter!(d => d.attributes.binding == MethodBinding.staticBinding).array);
      }
    }
    else if (auto structType = type.as!StructType) {
      return _lookup(
        null,
        vis == Visibility.public_
          ? structType.decl.members.lookup(identifier).filter!(d => d.visibility == Visibility.public_).array
          : structType.decl.members.lookup(identifier)
      );
    }
    return Lookup!(Decl[]).init;
}

auto lookup(alias predicate = null)(Expr expr, string identifier, Visibility vis = Visibility.public_) {

  Lookup!(Decl[]) lookup;
  if (auto metaType = expr.type.as!MetaType) {
    if (auto structType = metaType.type.as!StructType) {
      lookup = _lookup(
        expr,
        vis == Visibility.public_
          ? structType.decl.members.lookup(identifier).filter!(d => d.visibility == Visibility.public_ && d.attributes.binding == MethodBinding.staticBinding).array
          : structType.decl.members.lookup(identifier).filter!(d => d.attributes.binding == MethodBinding.staticBinding).array
        );
//
    }
  }
  else if (auto structType = expr.type.as!StructType) {
    lookup = Lookup!(Decl[])(
      expr,
      vis == Visibility.public_
        ? structType.decl.members.lookup(identifier).filter!(d => d.visibility == Visibility.public_ && d.attributes.binding == MethodBinding.dynamicBinding).array
        : structType.decl.members.lookup(identifier).filter!(d => d.attributes.binding == MethodBinding.dynamicBinding).array
      );
  }
  else lookup = _lookup(cast(Expr)null, (cast(Decl[])[]));
  static if (is(predicate: typeof(null))) {
    return _lookup(lookup.parent, lookup.decls.filter!predicate);
  } else {
    return lookup;
  }
}
