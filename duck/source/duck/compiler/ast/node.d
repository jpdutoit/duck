module duck.compiler.ast.node;

import duck.compiler;
import duck.util.list;

abstract class Node {
  alias NodeType = ubyte;
  NodeType nodeType();

  final override size_t toHash() @trusted const { return cast(size_t)cast(void*)this; }
  override bool opEquals(Object other) const {
      return this is other;
  }

  Slice source;
}

N withSource(N: Node)(N node, Node source) {
  node.source = source.source;
  return node;
}

N withSource(N: Node)(N node, Slice source) {
  node.source = source;
  return node;
}

N as(N : Node)(inout Node node) { return cast(N) node; }
T as(T : Type)(inout Type type) { return cast(T) type; }
D as(D : Decl)(inout Decl decl) { return cast(D) decl; }

import std.range.primitives;
auto as(N: Node, R)(R range) if (isInputRange!R && is(ElementType!R: Node)) {
  import std.algorithm.iteration : map;
  return range.map!(node => node.as!N);
}



private import std.meta : AliasSeq;

alias NodeTypes = AliasSeq!(
  ErrorExpr,
  RefExpr,
  InlineDeclExpr,
  ArrayLiteralExpr,
  StringValue,
  BoolValue,
  IntegerValue,
  FloatValue,
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
  ReturnStmt,
  IfStmt,
  WithStmt,

  DistinctDecl,
  BasicTypeDecl,
  ParameterDecl,
  CallableDecl,
  BuiltinVarDecl,
  TypeAliasDecl,
  VarDecl,
  TypeDecl,
  ArrayDecl,
  PropertyDecl,
  StructDecl,
  ModuleDecl,
  AliasDecl,
  ImportDecl,

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
