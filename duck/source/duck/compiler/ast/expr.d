module duck.compiler.ast.expr;

import duck.compiler;

abstract class Expr : Node {
  Type _type;

  @property
  final Type type(string file = __FILE__, int line = __LINE__) {
    ASSERT(_type, "Trying to use expression type before it is calculated", line, file);
    return _type;
  }

  @property
  final void type(Type type) {
    _type = type;
  }

  override string toString() {
    import duck.compiler.dbg.conv;
    return .toString(this);
  }

  CallExpr call(Expr[] arguments = []) {
    return new CallExpr(this, arguments, this.source);
  }

  CallExpr call(TupleExpr arguments) {
    return new CallExpr(this, arguments, this.source);
  }

  MemberExpr member(Slice name) {
    return new MemberExpr(this, name, this.source + name);
  }

  MemberExpr member(string name) {
    return new MemberExpr(this, name, this.source);
  }

  final T expect(T:Type)() {
    if (auto type = this._type.as!T) {
      return type;
    }
    error(this, "Expected a " ~ typeClassDescription!T);
    return null;
  }

  @property
  final bool hasError() {
    return (cast(ErrorType)this._type) !is null;
  }

  @property
  final bool hasType() {
    return this._type !is null;
  }
}

class ErrorExpr : Expr {
    mixin NodeMixin;
    this(Slice source) {
      this.source = source;
      this.type = ErrorType.create;
    }
}

class InlineDeclExpr : IdentifierExpr {
  mixin NodeMixin;

  DeclStmt declStmt;

  this(DeclStmt declStmt) {
    super(declStmt.decl.name);
    this.declStmt = declStmt;
  }
}

class RefExpr : Expr {
  mixin NodeMixin;

  Decl decl;
  Expr context;

  this(Decl decl, Expr context = null, Slice source = Slice()) {
    this.decl = decl;
    this.context = context;
    this.source = source;
  }
}

class LiteralExpr : Expr {
  mixin NodeMixin;

  Slice value;

  this(Token token) {
    this.source = token;
    this.value = token;
    switch (token.type) {
      case BoolLiteral:
        this.type = BoolType.create;
        break;
      case Number:
        import std.string: indexOf;
        if (token.slice.indexOf(".") >= 0)
          this.type = FloatType.create;
        else
          this.type = IntegerType.create;
        break;
      case StringLiteral:
        this.type = StringType.create;
        break;
      default:
        throw __ICE("Token is not a literal");
      }
  }
}

class ArrayLiteralExpr : Expr {
  mixin NodeMixin;

  Expr[] exprs;
  this(Expr[] exprs, Slice source = Slice()) {
    this.exprs = exprs;
    this.source = source;
  }
}

class TupleExpr : Expr {
  mixin NodeMixin;

  Expr[] elements;

  this(Expr[] elements, Type elementTypes = null) {
    this.type = elementTypes;
    this.elements = elements;
  }

  alias elements this;
}

class IdentifierExpr : Expr {
  mixin NodeMixin;

  Slice identifier;

  this(string identifier) {
    this.identifier = Slice(identifier);
    this.source = this.identifier;
  }

  this(Slice slice) {
    this.identifier = slice;
    this.source = this.identifier;
  }

  this(IdentifierExpr expr) {
    this.identifier = expr.identifier;
    this.source = this.identifier;
  }
}

class UnaryExpr : Expr {
  mixin NodeMixin;

  Slice operator;
  union {
    Expr operand;
    Expr[1] arguments;
  }

  this(Slice op, Expr operand, Slice source = Slice()) {
    operator = op;
    this.operand = operand;
    this.source = source;
  }
}

class BinaryExpr : Expr {
  mixin NodeMixin;

  Slice operator;
  union {
    struct {
      Expr left, right;
    }
    Expr[2] arguments;
  }

  this(Slice op, Expr left, Expr right, Slice source = Slice()) {
    this.operator = op;
    this.left = left;
    this.right = right;
    this.source = source;
  }
}

class PipeExpr : BinaryExpr {
  mixin NodeMixin;

  this(Slice op, Expr left, Expr right) {
    super(op, left, right);
  }
}

class AssignExpr : BinaryExpr {
  mixin NodeMixin;

  this(Slice op, Expr left, Expr right) {
    super(op, left, right);
  }
}

class MemberExpr : Expr {
  mixin NodeMixin;

  Expr context;
  Slice name;

  this(Expr context, string member, Slice source) {
    this(context, Slice(member), source);
  }

  this(Expr context, Slice member, Slice source) {
    this.context = context;
    this.name = member;
    this.source = source;
  }

}

class CastExpr: Expr {
  mixin NodeMixin;
  Expr expr;
  ref Type sourceType() { return expr._type; }
  Type targetType;

  this(Expr expr, Type targetType) {
    this.source = expr.source;
    this.expr = expr;
    this.targetType = targetType;
  }
}

class CallExpr : Expr {
  mixin NodeMixin;

  Expr callable;
  TupleExpr arguments;

  this(Expr callable, TupleExpr arguments, Slice source = Slice()) {
    this.callable = callable;
    this.arguments = arguments;
    this.source = source;
  }

  this(Expr callable, Expr[] arguments,  Slice source = Slice()) {
    this(callable, new TupleExpr(arguments), source);
  }
}

class ConstructExpr : CallExpr {
  mixin NodeMixin;

  this(Expr expr, TupleExpr arguments, Slice source = Slice()) {
    super(expr, arguments, source);
  }

  this(Expr callable, Expr[] arguments, Slice source = Slice()) {
    this(callable, new TupleExpr(arguments), source);
  }
}

class IndexExpr : Expr {
  mixin NodeMixin;

  Expr expr;
  TupleExpr arguments;

  this(Expr expr, TupleExpr arguments, Slice source = Slice()) {
    this.expr = expr;
    this.arguments = arguments;
    this.source = source;
  }
}
