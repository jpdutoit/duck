module duck.compiler.visitors.visit;

import std.traits, std.conv, std.typetuple;
import duck.compiler.dbg;
import duck.compiler.types;
import duck.compiler.ast;

R accept(R, N : Node, Visitor)(N node, auto ref Visitor visitor) {
  ASSERT(node, "Null node");
  switch(node.nodeType) {
    foreach(NodeType; NodeTypes) {
      static if (is(NodeType : N) && is(typeof(visitor.visit(cast(NodeType)node))))
        case NodeType._nodeTypeId: return visitor.visit(cast(NodeType)node);
    }
    default:
      ASSERT(false, "Not handled: " ~ node.classinfo.name);
      static if (!is(R:void)) return R.init;
  }
}

R accept(R, N : Type, Visitor)(N node, auto ref Visitor visitor) {
  ASSERT(node, "Null type");
  switch(node.kind) {
    foreach(TType; Types) {
      static if (is(TType : N) && is(typeof(visitor.visit(cast(TType)node))))
        case TType.Kind: return cast(R)(visitor.visit(cast(TType)node));
    }
    default:
      ASSERT(false, "Not handled: " ~ node.classinfo.name);
      static if (!is(R:void)) return R.init;
  }
}

auto accept(N : Node, Visitor)(N node, auto ref Visitor visitor) {
  alias Functions = typeof(__traits(getOverloads, Visitor, "visit"));
  alias R = CommonType!(staticMap!(ReturnType, Functions));
  return accept!(R,N,Visitor)(node, visitor);
}

auto accept(N : Type, Visitor)(N node, auto ref Visitor visitor) {
  alias Functions = typeof(__traits(getOverloads, Visitor, "visit"));
  alias R = CommonType!(staticMap!(ReturnType, Functions));
  return accept!(R,N,Visitor)(node, visitor);
}

template Visitor(T...) {
  alias ReturnTypes = staticMap!(ReturnType, T);
  //alias CommonReturnType =

  struct Visitor {
    alias ReturnType = CommonType!(ReturnTypes);

    mixin((() {
      auto code = "";
      foreach(i, t; T) {
        auto idx  = i.to!string;
        code ~= "  ReturnTypes["~ idx ~ "] visit(ParameterTypeTuple!(T["~idx~"])[0] n) { return T["~idx~"](n); }\n";
      }
      return code;
    })());

    ReturnType accept(N)(N n) if (is(N : Node) || is(N : Type)) {
      return .accept!(ReturnType, N, Visitor)(n, this);
    }
  }
}

// Case N > 2
template visit(T...) if (T.length > 2) {
  auto visit(N)(N n) { return Visitor!T().accept(n); };
}

// Case N == 1
template visit(alias T) if (isSomeFunction!(T)) {
  alias R = ReturnType!T;
  auto visit(N)(N node) {
    ASSERT(node, "Null node");
    if (auto n = cast(ParameterTypeTuple!(T)[0])node)
      return T(n);
    else {
      ASSERT(false, "Not handled: " ~ node.classinfo.name);
      static if (!is(R:void)) {
        return R.init;
      }
    }
  }
}

// Case N == 2
template visit(alias T, alias U) if (isSomeFunction!T && isSomeFunction!U) {
  alias TP = ParameterTypeTuple!(T)[0];
  alias UP = ParameterTypeTuple!(U)[0];
  alias R = CommonType!(ReturnType!T, ReturnType!U);

  R visit(N)(N node) {
    ASSERT(node, "Null node");
    static if (is(UP : TP)) {
      if (auto n = cast(UP)(node)) return U(n);
      if (auto n = cast(TP)(node)) return T(n);
    } else {
      if (auto n = cast(TP)(node)) return T(n);
      if (auto n = cast(UP)(node)) return U(n);
    }
    ASSERT(false, "Not handled: " ~ node.classinfo.name);
    static if (!is(R:void)) {
      return R.init;
    }
  }
}
