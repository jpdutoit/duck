module duck.compiler.parser;

import duck.compiler.lexer;
import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.context;
import duck.compiler.buffer;
import duck.compiler.dbg;

enum Precedence {
  Call = 140,
  Index = 140,
  MemberAccess = 140,
  Declare = 130,
  Unary = 120,
  Multiplicative = 110,
  Additive = 100,
  Comparison = 60,
  ShortCircuitAnd = 50,
  ShortCircuitOr = 40,
  Assignment = 30,
  Pipe  = 20
}

struct Parser {
  @disable this();

  this(Context context, Buffer buffer) {
      this.context = context;
      lexer = Lexer(context, buffer);
  }

  int rightAssociative(Token t) {
    switch (t.type) {
      case Tok!"+=":
      case Tok!"=": return true;
      default:
        return false;
    }
  }

  int precedence(Token t) {
    switch (t.type) {
      case Tok!":": return Precedence.Declare;
      case Tok!"(": return Precedence.Call;

      case Tok!"[": return Precedence.Index;
      case Tok!".": return Precedence.MemberAccess;

      case Tok!"*":
      case Tok!"/":
      case Tok!"%": return Precedence.Multiplicative;

      case Tok!"+":
      case Tok!"-": return Precedence.Additive;

      case Tok!">>": return Precedence.Pipe;

      case Tok!"=":
      case Tok!":=":
      case Tok!"+=": return Precedence.Assignment;

      case Tok!"==":
      case Tok!"!=":
      case Tok!">=":
      case Tok!"<=":
      case Tok!">":
      case Tok!"<": return Precedence.Comparison;

      case Tok!"and": return Precedence.ShortCircuitAnd;
      case Tok!"or": return Precedence.ShortCircuitOr;
      default:
      return -1;
    }
  }

  Lexer lexer;

  Token expect(Token.Type tokenType, string message, WhitespaceFilter filter = multiline) {
    //writefln("Expected %s found %s", tokenType, lexer.front.type);
    Token token = lexer.consume(tokenType, filter);
    if (!token) {
      context.error(lexer.front(filter), "%s not '%s'", message, lexer.front(filter).value);

      return None;
    }
    return token;
  }

  void expect(bool test, Slice slice, string message) {
    if (!test)
      context.error(slice, message);
  }

  Expr expect(Expr expr, string message) {
    return this.expect(expr, message, lexer.front);
  }
  Expr expect(Expr expr, string message, Slice location) {
      if (!expr) {
        context.error(location, message);
        return new ErrorExpr(location);
      }
      return expr;
  }

  T expect(T)(T node, string message) if (is(T: Node)) {
    if (!node) {
      context.error(lexer.front, message);
      //import core.stdc.stdlib : exit;
      //exit(2);
    }
    return node;
  }

  Slice sliceFrom(Slice start) {
    return lexer.sliceFrom(start);
  }

  ArrayLiteralExpr parseArrayLiteral() {
    auto token = lexer.front;
    if (lexer.consume(Tok!"[")) {
      Expr[] exprs;
      if (lexer.front.type != Tok!"]") {
        exprs ~= expect(parseExpression(), "Expected expression.");
        while (lexer.consume(Tok!",")) {
          exprs ~= expect(parseExpression(), "Expected expression.");
        }
      }
      expect(Tok!"]", "Expected ']'");
      return new ArrayLiteralExpr(exprs, sliceFrom(token));
    }
    return null;
  }

  Expr parsePrefix(WhitespaceFilter filter = multiline) {
    Token token = lexer.front(filter);
    switch(token.type) {
      case Tok!"[":
        return expect(parseArrayLiteral(), "Expected array literal.");
      case Number: {
        lexer.consume();
        Expr literal = LiteralExpr.create(token);
        // Unit parsing
        if (lexer.front(singleline).type == Identifier) {
          auto unit = new IdentifierExpr(lexer.consume(singleline));
          return new CallExpr(unit, new TupleExpr([literal]), token + unit.source);
        }
        return literal;
      }
      case BoolLiteral:
      case StringLiteral:
        lexer.consume;
        return LiteralExpr.create(token);
      case Identifier:
        lexer.consume;
        return new IdentifierExpr(token);
      case Tok!"(": {
        lexer.consume;
        // Grouping parentheses
        Expr expr = expect(parseExpression(), "Expected expression.");
        expect(Tok!")", "Expected ')'");
        return expr;
      }
      case Tok!"!":
      case Tok!"+", Tok!"-":
        lexer.consume;
        auto right = expect(parseExpression(Precedence.Unary - 1), "Expected expression.");
        return new UnaryExpr(token, right, token + right.source);
      default: break;
    }
    return null;
  }

  Expr[] parseExpressionTuple(Token.Type untilToken, string errorMessage) {
    Expr[] arguments;
    if (lexer.front.type != untilToken) {
      arguments ~= expect(parseExpression(), errorMessage);
      while (lexer.consume(Tok!",")) {
        arguments ~= expect(parseExpression(), errorMessage);
      }
    }
    return arguments;
  }

  CallExpr parseCall(Expr target) {
    lexer.expect(Tok!"(", "Expected '['");
    Expr[] arguments = parseExpressionTuple(Tok!")", "Expected function parameter");
    auto close = expect(Tok!")", "Expected ')'");
    return new CallExpr(target, new TupleExpr(arguments), target.source + close);
  }

  IndexExpr parseIndex(Expr target) {
    lexer.expect(Tok!"[", "Expected '['");
    Expr[] arguments = parseExpressionTuple(Tok!"]", "Expected index");
    auto close = expect(Tok!"]", "Expected ']'");
    auto call = new IndexExpr(target, new TupleExpr(arguments), target.source + close);
    return call;
  }

  ParameterDecl parseParameterDecl(Decl parent) {
    auto expr = parseExpression(Precedence.Declare);
    if (lexer.consume(Tok!":")) {
      auto identifier = cast(IdentifierExpr)expr;
      expect(identifier !is null, identifier.source, "Expected identifier");
      auto typeExpr = parseExpression(Precedence.Declare);
      return new ParameterDecl(typeExpr, identifier.identifier).withSource(sliceFrom(identifier.identifier));
    }

    if (!parent.isExternal) {
      context.error(expr.source, "Expected parameter name and type");
    }
    return new ParameterDecl(expr, Slice());
  }

  Expr parsePostfix(Expr left) {
    if (cast(InlineDeclExpr)left && lexer.front.type == Identifier) {
      return null;
    }
    Token token = lexer.front(multiline);
    int prec = precedence(token) + (rightAssociative(token) ? -1 : 0);

    if (token.line > statementStartToken.line && token.indent <= statementStartToken.indent)
          return null;

    switch (token.type) {
      case Tok!":":
        IdentifierExpr identifier = cast(IdentifierExpr)left;
        expect(identifier, "Expected identifier.");
        lexer.consume(Tok!":");
        if (!identifier) return null;

        Expr ctor = expect(parseExpression(singleline, prec), "Expected constructor expression on right side of declaration operator", token);
        Expr typeExpr;
        if (auto call = ctor.as!CallExpr) {
          typeExpr = call.callable;
        } else {
          typeExpr = ctor;
          ctor = null;
          auto equals = lexer.consume(Tok!"=");
          if (equals) {
            ctor = expect(parseExpression(Precedence.Assignment), "Expected expression on right side of assignment operator.", equals);
          }
        }

        auto varDecl = new VarDecl(typeExpr, identifier.identifier, ctor);
        varDecl.source = left.source + sliceFrom(token);
        return new InlineDeclExpr(new DeclStmt(varDecl));
      case Tok!"(":
        return parseCall(left);
      case Tok!"[":
        return parseIndex(left);
      case Tok!".": {
        lexer.consume;
        Token identifier = expect(Identifier, "Expected identifier following '.'");
        return left.member(identifier);
      }
      case Tok!":=": {
        IdentifierExpr identifier = cast(IdentifierExpr)left;
        expect(identifier, "Expected identifier.");
        lexer.consume(Tok!":=");
        if (!identifier) return null;

        Expr value = expect(parseExpression(prec), "Expected expression on right side of declaration opertaor");
        auto varDecl = new VarDecl(cast(Expr)null, identifier.identifier, value);
        varDecl.source = left.source +  sliceFrom(token);
        return new InlineDeclExpr(new DeclStmt(varDecl));
      }
      case Tok!"=", Tok!"+=":
        lexer.consume;
        return new AssignExpr(token, left, expect(parseExpression(prec), "Expected expression on right side of assignment operator.", token));
      case Tok!">>":
        lexer.consume;
        return new PipeExpr(token, left, expect(parseExpression(prec), "Expected expression on right side of pipe operator.", token));
      case Tok!"and", Tok!"or":
      case Tok!"==", Tok!"!=":
      case Tok!">=", Tok!"<=", Tok!">", Tok!"<":
      case Tok!"+", Tok!"-", Tok!"*", Tok!"/", Tok!"%":
        lexer.consume;
        auto right = expect(parseExpression(prec), "Expected expression on right side of binary operator.", token);
        return new BinaryExpr(token, left, right, left.source + right.source);
      default: break;
    }

    return null;
  }

  Expr continueExpression(Expr left, int minPrecedence = 0) {
    while (precedence(lexer.front) > minPrecedence) {
      auto newLeft = parsePostfix(left);
      if (!newLeft) return left;
      left = newLeft;
    }
    return left;
  }

  Expr parseExpression(int minPrecedence = 0) {
    return this.parseExpression(multiline, minPrecedence);
  }

  Expr parseExpression(WhitespaceFilter filter, int minPrecedence = 0) {
    auto start = lexer.front(filter);
    Expr left = parsePrefix(filter);
    if (!left) return left;

    return continueExpression(left, minPrecedence).withSource(sliceFrom(start));
  }

  BlockStmt parseBlock(BlockStmt blockStmt, TypeDecl parent = null) {
    if (lexer.front.type == Tok!"{") {
      auto start = lexer.front();
      lexer.consume();
      BlockStmt block = parseStatements(blockStmt, parent);
      lexer.expect(Tok!"}", "Expected '}'");
      return block.withSource(sliceFrom(start));
    }
    return null;
  }

  void parseCallableName(CallableDecl callable) {
    lexer.consume(Tok!"function");
    if (lexer.consume(Tok!"constructor")) {
      callable.name = Slice("__ctor");
      callable.isConstructor = true;
      return;
    }
    Token ident = expect(Identifier, "Expected identifier");

    if (ident.value == "operator") {
      callable.isOperator = true;
      switch (lexer.front.type) {
        case Tok!"-", Tok!"+", Tok!"*", Tok!"/", Tok!"%":
        case Tok!"!":
        case Tok!"and", Tok!"or":
        case Tok!"==", Tok!"!=":
        case Tok!">=", Tok!"<=", Tok!">", Tok!"<":
          ident = lexer.consume();
          break;
        case Tok!"[":
          ident = lexer.consume();
          if (lexer.front.type == Tok!"]") {
            ident = ident + lexer.front;
          }
          expect(Tok!"]", "Expected ']'");
          if (lexer.front.type == Tok!"=") {
            ident = ident + lexer.front;
            expect(Tok!"=", "Expected ']'");
          }
          break;
        default:
          context.error(lexer.front, "Expected an overridable operator.");
      }
    }
    callable.name = ident;
  }

  void parseCallableArgumentList(CallableDecl callable) {
    expect(Tok!"(", "Expected '('");
    if (lexer.front.type != Tok!")") {
      do {
        ParameterDecl decl = parseParameterDecl(callable);
        callable.parameters.add(decl);
      } while (lexer.consume(Tok!","));
    }
    expect(Tok!")", "Expected ')'");
  }

  void parseCallableReturnValue(CallableDecl callable) {
    if (lexer.consume(Tok!"->")) {
      expect(!callable.isConstructor, lexer.last, "Constructors may not have a return value.");
      callable.returnExpr = expect(parseExpression(Precedence.ShortCircuitOr), "Expected expression.");
    }
  }

  void parseCallableBody(CallableDecl callable) {
    callable.callableBody = parseBlock(new BlockStmt());
  }

  CallableDecl parseFunction(TypeDecl parent, DeclAttr attributes) {
    CallableDecl callable = new CallableDecl();
    callable.attributes = attributes;
    callable.parent = parent;
    if (parent && parent.isExternal) callable.attributes.external = true;

    Token start = lexer.front;
    parseCallableName(callable);
    parseCallableArgumentList(callable);
    parseCallableReturnValue(callable);
    callable.headerSource = sliceFrom(start);
    if (callable.isConstructor)
      callable.attributes.binding = MethodBinding.staticBinding;
    parseCallableBody(callable);

    return callable.withSource(sliceFrom(start));
  }

  CallableDecl parseSubscript(TypeDecl parent, DeclAttr attributes) {
    CallableDecl callable = new CallableDecl();
    callable.attributes = attributes;
    callable.parent = parent;
    if (parent && parent.isExternal) callable.attributes.external = true;

    Token start = lexer.front;
    parseCallableName(callable);
    parseCallableArgumentList(callable);
    parseCallableReturnValue(callable);
    callable.name = Slice("[]");
    callable.headerSource = sliceFrom(start);

    if (lexer.front.type == Tok!"{") {
      PropertyDecl propertyDecl = new PropertyDecl(callable.returnExpr, Slice("[]"));
      propertyDecl.parent = parent;
      if (parent && parent.isExternal) propertyDecl.attributes.external = true;

      foreach(decl; callable.parameters) {
        propertyDecl.context.add(decl);
      }

      VarDecl property = new VarDecl(new RefExpr(propertyDecl), Slice());
      parent.as!StructDecl.structBody.append(property);

      auto parentThis = parent.as!StructDecl.context.lookup("this").resolve();

      auto propertyRef = new RefExpr(property, parentThis);
      foreach(decl; callable.parameters) {
        propertyRef.contexts[decl] = new RefExpr(decl);
      }
      callable.returnExpr = propertyRef;

      propertyDecl.structBody = parseBlock(new BlockStmt(), propertyDecl);
    }

    return callable.withSource(sliceFrom(start));
  }

  CallableDecl parsePropertyAccessor(TypeDecl parent, DeclAttr attributes) {
    if (lexer.front.slice != "get" && lexer.front.slice != "set") { return null; }
    auto start = lexer.front;

    CallableDecl callable = new CallableDecl();
    callable.attributes = attributes;
    callable.isPropertyAccessor = true;
    callable.parent = parent;
    if (parent && parent.isExternal) callable.attributes.external = true;
    callable.name = lexer.consume();

    if (lexer.front.type == Tok!"(" || callable.name == "set") {
      parseCallableArgumentList(callable);
      expect(callable.parameters.length == 0 || callable.name != "get", sliceFrom(start), "Getter cannot have any arguments");
    }
    expect(callable.parameters.length == 1 || callable.name != "set", sliceFrom(start), "Setters must take 1 argument");

    parseCallableReturnValue(callable);
    if (!callable.returnExpr && callable.name == "get")
    if (auto propertyDecl = parent.as!PropertyDecl)
      callable.returnExpr = propertyDecl.typeExpr;

    parseCallableBody(callable);

    return callable.withSource(sliceFrom(start));
  }

  Decl parseAlias(TypeDecl parent, DeclAttr attributes) {
    Token start = lexer.front;

    expect(Tok!"alias", "Expected 'alias'");
    auto ident = expect(Identifier, "Expected 'identifier'");

    Decl decl;
    if (lexer.consume(Tok!"=")) {
      auto expr = expect(parseExpression(Precedence.Assignment), "Expected expression on right side of alias assignment");
      decl = new AliasDecl(ident, expr);
    }
    else if (lexer.consume(Tok!":")) {
      auto expr = expect(parseExpression(Precedence.Assignment), "Expected expression on right side of alias assignment");
      decl = new TypeAliasDecl(ident, expr);
    }
    else {
      context.error(lexer.front, "Expected '=' or ':'");
    }

    decl.attributes = attributes;
    decl.parent = parent;

    return decl.withSource(sliceFrom(start));
  }

  DistinctDecl parseDistinct(TypeDecl parent, DeclAttr attributes) {
    Token start = lexer.front;

    expect(Tok!"distinct", "Expected 'distinct'");
    auto ident = expect(Identifier, "Expected 'identifier'");
    expect(Tok!":", "Expected ':'");
    auto type = expect(parseExpression(Precedence.Unary), "Expected type expression");

    auto decl = new DistinctDecl(ident, type);
    decl.attributes = attributes;
    decl.parent = parent;

    return decl.withSource(sliceFrom(start));
  }

  DeclAttr parseAttributes(DeclAttr base) {
    if (lexer.front.isAttribute) {
      bool foundVisibilityAttr, foundStorageAttr, foundMethodBindingAttr;
      do {
        if (lexer.front.type == Tok!"extern") {
          lexer.consume();
          expect(!base.external, lexer.front, "Duplicate extern attribute");
          base.external = true;
        }
        else if (lexer.front.type == Tok!"@output") {
          lexer.consume();
          expect(!base.output, lexer.front, "Duplicate @output attribute");
          base.output = true;
        }
        else if (lexer.front.isVisibilityAttribute) {
          expect(!foundVisibilityAttr, lexer.front, "Duplicate visibility attribute");
          foundVisibilityAttr = true;
          base.visibility = lexer.consume().visibility;
        }
        else if (lexer.front.isStorageClassAttribute) {
          expect(!foundStorageAttr, lexer.front, "Duplicate storage class attribute");
          foundStorageAttr = true;
          base.storage = lexer.consume().storageClass;
        }
        else if (lexer.front.isMethodBindingAttribute) {
          expect(!foundMethodBindingAttr, lexer.front, "Duplicate method binding attribute");
          foundMethodBindingAttr = true;
          base.binding = lexer.consume().methodBinding;
        }
        else context.error(lexer.consume(), "Unrecognized attribute");
      } while (lexer.front.isAttribute);
    }
    return base;
  }

  StructDecl parseStruct(TypeDecl parent, DeclAttr attributes) {
    auto start = lexer.front;
    lexer.expect(Tok!"struct", "Expected struct");
    Token ident = expect(Identifier, "Expected identifier");

    StructDecl structDecl = new StructDecl(ident);
    structDecl.attributes = attributes;
    structDecl.parent = parent;

    if (!structDecl.isExternal || lexer.front.type == Tok!"{") {
      lexer.expect(Tok!"{", "Expected '{");
      structDecl.structBody = new BlockStmt();
      parseStatements(structDecl.structBody, structDecl);
      lexer.expect(Tok!"}", "Expected '}'");
    }

    return structDecl.withSource(sliceFrom(start));
  }

  ModuleDecl parseModule(TypeDecl parent, DeclAttr attributes) {
    auto start = lexer.front;
    lexer.expect(Tok!"module", "Expected module");
    Token ident = expect(Identifier, "Expected identifier");

    ModuleDecl structDecl = new ModuleDecl(ident);
    structDecl.attributes = attributes;
    structDecl.parent = parent;

    lexer.expect(Tok!"{", "Expected '{");
    structDecl.structBody = new BlockStmt();
    parseStatements(structDecl.structBody, structDecl);
    lexer.expect(Tok!"}", "Expected '}'");

    return structDecl.withSource(sliceFrom(start));
  }

  ImportDecl parseImport(TypeDecl parent, DeclAttr attributes) {
    auto start = lexer.front;
    lexer.expect(Tok!"import", "Expected import");
    auto ident = expect(StringLiteral, "Expected library name");

    auto childContext = ident.length > 2 ? context.createImportContext(ident[1..$-1]) : null;
    auto decl = new ImportDecl(ident, childContext);

    decl.attributes = attributes;
    decl.parent = parent;

    return decl.withSource(sliceFrom(start));
  }

  Stmt parseReturnStmt() {
    auto start = lexer.front;
    lexer.expect(Tok!"return", "Expected return");
    auto expr = parseExpression(singleline);
    return new ReturnStmt(expr).withSource(sliceFrom(start));
  }

  Stmt parseIf() {
    auto start = lexer.front;
    lexer.expect(Tok!"if", "Expected 'if'");
    auto condition = expect(parseExpression(singleline, Precedence.ShortCircuitOr-1), "Expected expression.");
    Stmt trueBody = expect(parseStatement(null), "Expected statement after 'if'");
    Stmt falseBody;
    if (lexer.consume(Tok!"else")) {
      falseBody = expect(parseStatement(null), "Expected statement after 'else'");
    }
    return new IfStmt(condition, trueBody, falseBody).withSource(sliceFrom(start));
  }

  Stmt parseWith() {
    auto start = lexer.front;
    lexer.expect(Tok!"with", "Expected 'with'");
    auto valueExpr = expect(parseExpression(singleline, Precedence.Assignment-1), "Expected expression.");
    Stmt withBody = expect(parseStatement(null), "Expected statement after 'with'");
    return new WithStmt(valueExpr, withBody);
  }

  Token statementStartToken;

  Stmt parseStatement(TypeDecl parent, DeclAttr attributes = DeclAttr.init) {
    auto oldStatementStart = statementStartToken;
    scope(exit) statementStartToken = oldStatementStart;
    auto front = statementStartToken = lexer.front(multiline);
    switch (front.type) {
      case Tok!";":
        context.error(lexer.consume(Tok!";", multiline), "Use {} for empty statements.");
        return new BlockStmt();
      case Tok!"import":   return new DeclStmt(parseImport(parent, attributes));
      case Tok!"return":   return parseReturnStmt();
      case Tok!"if":       return parseIf();
      case Tok!"with":     return parseWith();
      case Tok!"{":        return expect(parseBlock(new ScopeStmt()), "Block expected");
      case Tok!"struct":   return new DeclStmt(parseStruct(parent, attributes));
      case Tok!"module":   return new DeclStmt(parseModule(parent, attributes));
      case Tok!"function": return new DeclStmt(parseFunction(parent, attributes));
      case Tok!"constructor": return new DeclStmt(parseFunction(parent, attributes));
      case Tok!"alias":    return new DeclStmt(parseAlias(parent, attributes));
      case Tok!"distinct":  return new DeclStmt(parseDistinct(parent, attributes));
      case Identifier:
        auto name = front.slice;
        if (name == "get" || name == "set") {
          return new DeclStmt(parsePropertyAccessor(parent, attributes));
        }
        else if (name == "subscript") {
          return new DeclStmt(parseSubscript(parent, attributes));
        }
        goto default;
      default: {
        auto expr = parseExpression();
        if (!expr) return null;

        auto declExpr = cast(InlineDeclExpr)expr;
        if (!declExpr) return new ExprStmt(expr);

        VarDecl varDecl = (cast(VarDecl)(declExpr.declStmt.decl));
        varDecl.attributes = attributes;
        varDecl.parent = parent;
        if (parent && parent.isExternal) varDecl.attributes.external = true;

        if (lexer.front.type == Tok!"{") {
          StructDecl propertyDecl = new PropertyDecl(varDecl.typeExpr, varDecl.name);
          propertyDecl.attributes = varDecl.attributes;
          propertyDecl.parent = parent;
          varDecl.typeExpr = new RefExpr(propertyDecl);
          propertyDecl.structBody = new BlockStmt();
          parseBlock(propertyDecl.structBody, propertyDecl);
        }
        return declExpr.declStmt;
      }
    }
  }

  BlockStmt parseStatements(BlockStmt block, TypeDecl parent, DeclAttr blockAttr = DeclAttr.init) {
    auto start = lexer.front;
    while (true) {
      bool hasAttribute = lexer.front.isAttribute;
      Token firstAttributeToken = lexer.front;
      DeclAttr nextAttr = parseAttributes(blockAttr);
      Slice attributeSlice = sliceFrom(firstAttributeToken);

      if (lexer.consume(Tok!":")) {
        expect(hasAttribute, lexer.last, "Expected attribute before ':'");
        blockAttr = nextAttr;
        continue;
      }
      if (lexer.consume(Tok!"{")) {
        expect(hasAttribute, lexer.front, "Expected attribute before '{'");
        parseStatements(block, parent, nextAttr);
        lexer.expect(Tok!"}", "Expected '}'");
        continue;
      }

      auto stmtStart = lexer.front;
      Stmt stmt = parseStatement(parent, nextAttr);
      if (!stmt) {
        expect(!hasAttribute, attributeSlice, "Declaration expected after attribute");
        break;
      }

      if (!(lexer.consume(Tok!"\n", singleline) || lexer.consume(EOF, singleline) || lexer.front.type == Tok!"}")) {
        lexer.expect(Tok!";", "Expected ';'");
      }

      if (auto declStmt = stmt.as!DeclStmt) {
        declStmt.source += firstAttributeToken;
      } else {
        expect(!hasAttribute, attributeSlice, "Only declarations may have attributes");
      }
      block.append(stmt);
    }
    block.source += sliceFrom(start);
    return block;
  }

  Library parseLibrary() {
    auto prog = new Library(parseStatements(new BlockStmt(), null));
    if (context.options.includePrelude) {
      prog.stmts.prepend(new DeclStmt(new ImportDecl(Slice("\"std\""), context.createStdlibContext("std.duck"))));
    }
    auto builtinDecl = new ImportDecl(Slice("\"builtin\""), context.createBuiltinContext());
    builtinDecl.attributes.visibility = Visibility.private_;
    prog.stmts.prepend(new DeclStmt(builtinDecl));
    lexer.expect(EOF, "Expected end of file");
    return prog;
  }

  Context context;
}
