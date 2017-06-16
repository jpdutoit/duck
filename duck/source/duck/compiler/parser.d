module duck.compiler.parser;

import duck.compiler.lexer;
import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.context;
import duck.compiler.buffer;

enum Precedence {
  Call = 140,
  Index = 140,
  MemberAccess = 140,
  Declare = 130,
  Unary = 120,
  Multiplicative = 110,
  Additive = 100,
  Comparison = 60,
  Assignment = 30,
  Pipe  = 20
};

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
      case Tok!"+=": return Precedence.Assignment;

      case Tok!"==":
      case Tok!"!=":
      case Tok!">=":
      case Tok!"<=":
      case Tok!">":
      case Tok!"<": return Precedence.Comparison;
      default:
      return -1;
    }
  }

  Lexer lexer;

  Token expect(Token.Type tokenType, string message) {
    //writefln("Expected %s found %s", tokenType, lexer.front.type);
    Token token = lexer.consume(tokenType);
    if (!token) {
      context.error(lexer.front, "%s not '%s'", message, lexer.front.value);

      return None;
    }
    return token;
  }

  Expr expect(Expr expr, string message) {
      if (!expr) {
        context.error(lexer.front, message);
        return new ErrorExpr(lexer.front);
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
      return new ArrayLiteralExpr(exprs, lexer.sliceFrom(token));
    }
    return null;
  }

  Expr parsePrefix() {
    Token token = lexer.front;
    switch(token.type) {
      case Tok!"[":
        return expect(parseArrayLiteral(), "Expected array literal.");
      case Number: {
        lexer.consume;
        Expr literal = new LiteralExpr(token);
        // Unit parsing
        if (lexer.front.type == Identifier) {
          auto unit = new IdentifierExpr(lexer.consume);
          return new CallExpr(unit, new TupleExpr([literal]), null, token + unit.source);
        }
        return literal;
      }
      case StringLiteral:
        lexer.consume;
        return new LiteralExpr(token);
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
      case Tok!"+":
      case Tok!"-":
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
    auto call = new CallExpr(target, new TupleExpr(arguments), null, target.source + close);
    return call;
  }

  IndexExpr parseIndex(Expr target) {
    lexer.expect(Tok!"[", "Expected '['");
    Expr[] arguments = parseExpressionTuple(Tok!"]", "Expected index");
    expect(Tok!"]", "Expected ']'");
    auto call = new IndexExpr(target, new TupleExpr(arguments));
    return call;
  }

  VarDecl parseVarDecl() {
    if (lexer.front.type == Identifier && lexer.peek(1).type == Tok!":") {
      auto identifier = lexer.consume;
      lexer.expect(Tok!":", "Expected ':'");
      auto typeExpr = new TypeExpr(parseExpression(Precedence.Unary));
      return new VarDecl(typeExpr, identifier);
    }
    return null;
  }

  ParameterDecl parseParameterDecl(Decl parent) {
    if (lexer.front.type == Identifier && lexer.peek(1).type == Tok!":") {
      auto identifier = lexer.consume;
      lexer.expect(Tok!":", "Expected ':'");
      auto typeExpr = new TypeExpr(parseExpression(Precedence.Unary));
      return new ParameterDecl(typeExpr, identifier);
    }
    return null;
  }

  void parseCallableArgumentList(CallableDecl callable, bool isExtern) {
    expect(Tok!"(", "Expected '('");
    if (lexer.front.type != Tok!")") {
      do {
        ParameterDecl decl = parseParameterDecl(callable);
        if (decl) {
          callable.parameters.add(decl);
          callable.parameterTypes ~= decl.typeExpr;
        }
        else {
          if (!isExtern) {
            context.error(lexer.front, "Expected parameter name");
          }
          auto typeExpr = new TypeExpr(parseExpression(Precedence.Unary));
          callable.parameterTypes ~= typeExpr;
          callable.parameters.add(new ParameterDecl(typeExpr, Slice()));
        }
      } while (lexer.consume(Tok!","));
    }
    expect(Tok!")", "Expected ')'");
  }

  Expr parsePostfix(Expr left) {
    if (cast(InlineDeclExpr)left && lexer.front.type == Identifier) {
      return null;
    }
    Token token = lexer.front;
    //writefln("parseInfix: %s", token.value);
    int prec = precedence(token) + (rightAssociative(token) ? -1 : 0);
    switch (token.type) {
      case Tok!":":
        IdentifierExpr identifier = cast(IdentifierExpr)left;
        expect(identifier, "Expected identifier.");
        lexer.consume(Tok!":");
        if (!identifier) return null;

        Expr ctor = expect(parseExpression(prec), "Expected constructor expression on right side of declaration opertaor");
        Expr typeExpr;
        CallExpr call = cast(CallExpr)ctor;
        if (call) {
          typeExpr = call.callable;
        } else {
          typeExpr = ctor;
          ctor = null;
        }

        return new InlineDeclExpr(new VarDeclStmt(new VarDecl(new TypeExpr(typeExpr), identifier.identifier), ctor));
      case Tok!"(":
        // Call parenthesis
        return parseCall(left);
      case Tok!"[":
        return parseIndex(left);
      case Tok!".": {
        lexer.consume;
        //writefln("%s %s", Identifier, Identifier);
        Token identifier = expect(Identifier, "Expected identifier following '.'");
        return left.member(identifier);
      }
      case Tok!"=":
      case Tok!"+=":
        lexer.consume;
        return new AssignExpr(token, left, expect(parseExpression(prec), "Expected expression on right side of assignment operator."));
      case Tok!">>":
        lexer.consume;
        return new PipeExpr(token, left, expect(parseExpression(prec), "Expected expression on right side of pipe operator."));
      case Tok!"==":
      case Tok!"!=":
      case Tok!">=":
      case Tok!"<=":
      case Tok!">":
      case Tok!"<":
      case Tok!"+":
      case Tok!"-":
      case Tok!"*":
      case Tok!"/":
      case Tok!"%":
        lexer.consume;
        auto right = expect(parseExpression(prec), "Expected expression on right side of binary operator.");
        return new BinaryExpr(token, left, right, left.source + right.source);
      default: break;
    }

    return null;
  }

  Expr parseExpression(int minPrecedence = 0) {
    //writefln("parseExpression: %s %s", lexer.front, minPrecedence);
    Expr left = parsePrefix();
    if (!left) return left;
    //writefln("Left: %s %s", left, lexer.front);

    while (precedence(lexer.front) > minPrecedence) {
      auto newLeft = parsePostfix(left);
      if (!newLeft) return left;
      left = newLeft;
      //writefln("Left: %s %s", left, lexer.front);
    }
    return left;
  }

  Stmt parseBlock() {
    if (lexer.front.type == Tok!"{") {
      lexer.consume();
      Stmt statements = parseStatements();
      lexer.expect(Tok!"}", "Expected '}'");
      return statements;
    }
    return null;
  }

  Decl parseField(StructDecl structDecl)
  {
    if (lexer.front.type == Identifier && lexer.peek(1).type == Tok!":") {
      auto identifier = lexer.consume;
      lexer.expect(Tok!":", "Expected ':'");
      auto typeExpr = parseExpression(Precedence.Declare);

      if (!structDecl.external && lexer.consume(Tok!"=")) {
        Expr value = expect(parseExpression(), "Expected expression.");
        return new FieldDecl(typeExpr, identifier, value, structDecl);
      }

      return new FieldDecl(typeExpr, identifier, null, structDecl);
    }
    return null;
  }

  CallableDecl parseMethod(StructDecl structDecl)
  {
    bool isCtor = false;
    CallableDecl decl;
    if (lexer.front.type == Tok!"constructor") {
      isCtor = true;
      decl = new CallableDecl(lexer.front);
      lexer.consume();
    }
    else {
      if (!expect(Tok!"function", "Expected keyword function"))
        return null;
      auto name = expect(Identifier, "Expected identifier");
      decl = new CallableDecl(name);
    }
    decl.isMethod = true;

    parseCallableArgumentList(decl, structDecl.external);

    Stmt methodBody;
    if (structDecl.external) {
      expect(Tok!";", "Expected ';'");
    } else {
      methodBody = expect(parseBlock(), "Expected function body");
    }

    decl.callableBody = methodBody;
    decl.parentDecl = structDecl;
    return decl;

  }

  Stmt parseFunction(bool isExtern = false) {
    lexer.expect(Tok!"function", "Expected module");
    Token ident = expect(Identifier, "Expected identifier");
    CallableDecl func = new CallableDecl(ident);
    if (ident.value == "operator") {
      switch (lexer.front.type) {
        case Tok!"-":
        case Tok!"+":
        case Tok!"*":
        case Tok!"/":
        case Tok!"%":
        case Tok!"!":
        case Tok!"==":
        case Tok!"!=":
        case Tok!">=":
        case Tok!"<=":
        case Tok!">":
        case Tok!"<":
          func.isOperator = true;
          ident = lexer.consume();
          break;
        default:
          context.error(lexer.front, "Expected an overridable operator.");
      }
    }
    func.name = ident;
    func.isExternal = isExtern;

    parseCallableArgumentList(func, isExtern);


    if (lexer.consume(Tok!"->")) {
      func.returnExpr = expect(parseExpression(Precedence.Comparison), "Expected expression.");
    }

    if (!isExtern) {
      func.callableBody = parseBlock();
    }

    if (!func.callableBody) {
      lexer.expect(Tok!";", "Expected ';'");
    }

    auto stmt = new TypeDeclStmt(ident, func);
    this.decls ~= stmt;


    return stmt;
  }

  Stmt parseStruct(bool isExtern = false) {
    lexer.expect(Tok!"struct", "Expected struct");
    Token ident = expect(Identifier, "Expected identifier");

    auto mod = StructType.create(ident);
    StructDecl structDecl = new StructDecl(mod, ident);
    mod.decl = structDecl;
    structDecl.external = isExtern;

    if (lexer.consume(Tok!"{")) {
      while (lexer.front.type != Tok!"}") {
        if (lexer.front.type == Tok!"function") {
          CallableDecl method = parseMethod(structDecl);
          structDecl.decls.define(method.name, method);
        } else {
          Decl field = parseField(structDecl);
          if (!field) break;
          structDecl.decls.define(field.name, field);
          lexer.expect(Tok!";", "Expected ';'");
        }
      }
      expect(Tok!"}", "Expected '}'");
    } else {
      lexer.expect(Tok!";", "Expected ';'");
    }

     //new NamedType(ident.value.idup, new ModuleType())
    auto stmt = new TypeDeclStmt(ident, structDecl);
    this.decls ~= stmt;
    return stmt;
  }

  Stmt parseModule(bool isExtern = false) {
    lexer.expect(Tok!"module", "Expected module");
    Token ident = expect(Identifier, "Expected identifier");
    expect(Tok!"{", "Expected '}'");

    auto mod = ModuleType.create(ident);
    ModuleDecl structDecl = new ModuleDecl(mod, ident);
    mod.decl = structDecl;
    structDecl.external = isExtern;

    while (lexer.front.type != Tok!"}") {
      if (lexer.front.type == Tok!"constructor" || lexer.front.type == Tok!"function") {
        CallableDecl method = parseMethod(structDecl);
        if (method.name == "constructor") {
            structDecl.ctors.add(method);
        }
        else
          structDecl.decls.define(method.name, method);
      } else {
        Decl field = parseField(structDecl);
        if (!field) break;
        structDecl.decls.define(field.name, field);
        lexer.expect(Tok!";", "Expected ';'");
      }
    }
    expect(Tok!"}", "Expected '}'");

    //new NamedType(ident.value.idup, new ModuleType())
    auto stmt = new TypeDeclStmt(ident, structDecl);
    this.decls ~= stmt;
    return stmt;
    //decls ~= structDecl;
  }

  ImportStmt parseImport() {
    lexer.expect(Tok!"import", "Expected import");
    Token ident;
    ident = expect(StringLiteral, "Expected library name");
    if (!ident) return null;
    lexer.expect(Tok!";", "Expected ';'");
    return new ImportStmt(ident);
  }

  Stmt parseReturnStmt() {
    lexer.expect(Tok!"return", "Expected return");
    auto expr = expect(parseExpression(), "Expected expression.");
    lexer.expect(Tok!";", "Expected ';'");
    auto r = new ReturnStmt(expr);
    return r;
  }

  Stmt parseStatement() {
    switch (lexer.front.type) {
      case Tok!"import":
        return parseImport();
      case Tok!"extern":
        lexer.consume();
        if (lexer.front.type == Tok!"module")
          return parseModule(true);
        else if (lexer.front.type == Tok!"struct")
          return parseStruct(true);
        else if (lexer.front.type == Tok!"function") {
          auto f = parseFunction(true);
          return f;
        }
        else {
          InlineDeclExpr inlineDeclExpr = cast(InlineDeclExpr)parseExpression();
          if (inlineDeclExpr) {
            lexer.expect(Tok!";", "Expected ';'");
            VarDecl varDecl = (cast(VarDecl)(inlineDeclExpr.declStmt.decl));
            varDecl.external = true;
            return inlineDeclExpr.declStmt;
          }
          expect(inlineDeclExpr, "Expected declaration.");
          return null;
        }
      case Tok!"return":
        return parseReturnStmt();
      case Tok!"struct":
        return parseStruct();
      case Tok!"module":
        return parseModule();
      case Tok!"function": {
        auto f = parseFunction();
        return f;
      }
      case Tok!"{":
        // Block statement
        return expect(parseBlock(), "Block expected");
      default: {
        // Expression statements
        Expr expr = parseExpression();
        if (expr) {
          lexer.expect(Tok!";", "Expected ';'");
          while (lexer.consume(Tok!";")) {}
          return new ExprStmt(expr);
        }
        return null;
      }
    }
  }

  Stmt parseStatements(bool createScope = true) {
    Stmt[] statements;
    while (true) {
      Stmt stmt = parseStatement();
      if (!stmt)
        break;
      statements ~= stmt;
    }
    Stmts stmts = new Stmts(statements);
    return createScope ? new ScopeStmt(stmts) : stmts;
  }

  Library parseLibrary() {
    auto prelude = new ImportStmt(context.token(StringLiteral, "\"prelude\""));
    if (context.includePrelude)
      decls ~= prelude;
    auto stmt = parseStatements(false);
    auto prog = new Library(context.includePrelude ? [prelude, stmt] : [stmt], decls);
    //auto prog = new Library([prelude, parseStatements()]);
    lexer.expect(EOF, "Expected end of file");
    return prog;
  }

  Node[] decls;
  Context context;
}
