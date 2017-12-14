module duck.compiler.ast.node;

import duck.compiler;
import duck.util.list;

abstract class Node {
  alias NodeType = ubyte;
  NodeType nodeType();

  final override size_t toHash() @trusted { return cast(size_t)cast(void*)this; }
  final override bool opEquals(Object other) {
      return this is other;
  }

  Slice source;
};

N withSource(N: Node)(N node, Node source) {
  node.source = source.source;
  return node;
}

N withSource(N: Node)(N node, Slice source) {
  node.source = source;
  return node;
}

N as(N : Node)(Node node) { return cast(N) node; }
T as(T : Type)(Type type) { return cast(T) type; }
D as(D : Decl)(Decl decl) { return cast(D) decl; }

import std.range.primitives;
auto as(N: Node, R)(R range) if (isInputRange!R && is(ElementType!R: Node)) {
  import std.algorithm.iteration;
  return range.map!(node => node.as!N);
}



private import std.meta : AliasSeq;

alias NodeTypes = AliasSeq!(
  ErrorExpr,
  RefExpr,
  InlineDeclExpr,
  ArrayLiteralExpr,
  LiteralExpr,
  IdentifierExpr,
  UnaryExpr,
  AssignExpr,
  BinaryExpr,
  PipeExpr,
  MemberExpr,
  CallExpr,
  ConstructExpr,
  TupleExpr,
  IndexExpr,
  CastExpr,

  BlockStmt,
  ExprStmt,
  DeclStmt,
  ScopeStmt,
  ImportStmt,
  ReturnStmt,
  IfStmt,

  OverloadSet,
  BasicTypeDecl,
  ParameterDecl,
  CallableDecl,
  BuiltinVarDecl,
  VarDecl,
  TypeDecl,
  ArrayDecl,
  FieldDecl,
  StructDecl,
  ModuleDecl,

  Library);

mixin template NodeMixin() {
  private import std.typetuple: staticIndexOf;
  static enum _nodeTypeId = staticIndexOf!(typeof(this), NodeTypes);
  static if (_nodeTypeId < 0) {
    //#TODO:0 Do it right
    static assert(false, "Expected type " ~ typeof(this).stringof ~ " to be in NodeTypes list.");
  }
  override NodeType nodeType() { return _nodeTypeId; };
};
