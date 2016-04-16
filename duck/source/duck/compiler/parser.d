module duck.compiler.parser;

import duck.compiler.lexer;
import duck.compiler.ast;
import duck.compiler.types;
import duck.compiler.context;
import duck.compiler.buffer;

enum Precedence {
  Call = 140,
  MemberAccess = 140,
  Unary = 120,
  Multiplicative = 110,
  Additive = 100,
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
      case Identifier: return Precedence.Call;
      case Tok!"(": return Precedence.Call;
      case Tok!".": return Precedence.MemberAccess;
      case Tok!"*": return Precedence.Multiplicative;
      case Tok!"/": return Precedence.Multiplicative;
      case Tok!"%": return Precedence.Multiplicative;
      case Tok!"+": return Precedence.Additive;
      case Tok!"-": return Precedence.Additive;
      case Tok!">>": return Precedence.Pipe;
      case Tok!"=": return Precedence.Assignment;
      case Tok!"+=": return Precedence.Assignment;
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
        exprs ~= expect(parseExpression(), "Expression expected");
        while (lexer.consume(Tok!",")) {
          exprs ~= expect(parseExpression(), "Expression expected");
        }
      }
      expect(Tok!"]", "Expected ']'");
      return new ArrayLiteralExpr(exprs);
    }
    return null;
  }
  Expr parsePrefix() {
    switch (lexer.front.type) {
        case Tok!"[":
          return expect(parseArrayLiteral(), "Expected array literal.");
        default: break;
    }

    Token token = lexer.front;
    switch(token.type) {
      case Number: {
        lexer.consume;
        Expr literal = new LiteralExpr(token);
        // Unit parsing
        if (lexer.front.type == Identifier) {
          return new CallExpr(new IdentifierExpr(lexer.consume), new TupleExpr([literal]));
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
        Expr expr = parseExpression();
        expect(Tok!")", "Expected ')'");
        return expr;
      }
      case Tok!"+":
      case Tok!"-":
        lexer.consume;
        return new UnaryExpr(token, parseExpression(Precedence.Unary - 1));
      default: break;
    }
    return null;
  }


  CallExpr parseCall(Expr target) {
    Expr[] arguments;
    if (lexer.front.type != Tok!")") {
      arguments ~= parseExpression();
      while (lexer.consume(Tok!",")) {
        arguments ~= parseExpression();
      }
    }
    expect(Tok!")", "Expected ')'");
    return new CallExpr(target, new TupleExpr(arguments));
  }

  Expr parsePostfix(Expr left) {
    if (cast(InlineDeclExpr)left && lexer.front.type == Identifier) {
      return null;
    }
    Token token = lexer.front;
    //writefln("parseInfix: %s", token.value);
    int prec = precedence(token) + (rightAssociative(token) ? -1 : 0);
    switch (token.type) {
      case Identifier: {
        lexer.consume;
        // Inline declaration
        CallExpr ctor;
        if (lexer.consume(Tok!"(")) {
          ctor = parseCall(left);
        } else {
          ctor = new CallExpr(left, new TupleExpr([]));
        }
        return new InlineDeclExpr(token, new VarDeclStmt(token, new VarDecl(left, token), ctor));
      }
      case Tok!"(":
        lexer.consume;
        // Call parenthesis
        return parseCall(left);
      case Tok!".": {
        lexer.consume;
        //writefln("%s %s", Identifier, Identifier);
        Token identifier = expect(Identifier, "Expected identifier following '.'");
        return new MemberExpr(left, identifier);
      }
      case Tok!"=":
      case Tok!"+=":
        lexer.consume;
        return new AssignExpr(token, left, parseExpression(prec));
      case Tok!">>":
        lexer.consume;
        return new PipeExpr(token, left, parseExpression(prec));
      case Tok!"+":
      case Tok!"-":
      case Tok!"*":
      case Tok!"/":
      case Tok!"%":
        lexer.consume;
        return new BinaryExpr(token, left, parseExpression(prec));
        //return factory.binaryOp(token, left, parseExpression(prec));
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
    Token type = expect(Identifier, "Identifier expected");
    Token name = expect(Identifier, "Field name expected");

    if (!type && !name) return null;
    if (!structDecl.external && lexer.consume(Tok!"=")) {
      // Handle init values
      Expr value = expect(parseExpression(), "Expression expected");
      return new FieldDecl(new TypeExpr(new IdentifierExpr(type)), name, value, structDecl);
    }
    else if (lexer.consume(Tok!":")) {
      Expr target = expect(parseExpression(), "Expression expected");
      Token thisToken = context.token(Identifier, "this");
      return new MacroDecl(new TypeExpr(new IdentifierExpr(type)), name, [new TypeExpr(new RefExpr(thisToken, structDecl))], [thisToken], target);
      //return new AliasDecl(new IdentifierExpr(type), name, target, structDecl);
    }

    return new FieldDecl(new TypeExpr(new IdentifierExpr(type)), name, null, structDecl);
    //return new FieldDecl(new NamedType(type.value.idup, new StructType(type)), name);
  }

  MethodDecl parseMethod(StructDecl structDecl)
  {
    if (!expect(Tok!"function", "Expected keyword function"))
      return null;
    Token name = expect(Identifier, "Expected identifier");
    expect(Tok!"(", "Expected '('");
    expect(Tok!")", "Expected ')'");
    Stmt methodBody;
    if (structDecl.external) {
      expect(Tok!";", "Expected ';'");
    } else {
      methodBody = expect(parseBlock(), "Expected function body");
    }
    return new MethodDecl(FunctionType.create(VoidType.create, TupleType.create([])), name, methodBody, structDecl);
  }

  TypeDeclStmt parseFunction(bool isExtern = false) {
    lexer.expect(Tok!"function", "Expected module");
    Token ident = expect(Identifier, "Expected identifier");
    FunctionDecl func = new FunctionDecl(ident);
    if (ident.value == "operator") {
      switch (lexer.front.type) {
        case Tok!"-":
        case Tok!"+":
        case Tok!"*":
        case Tok!"/":
        case Tok!"%":
          ident = lexer.consume();
          break;
        default:
          context.error(lexer.front, "Expected an overridable operator.");
      }
    }
    func.name = ident;
    func.external = isExtern;

    expect(Tok!"(", "Expected '('");
    if (lexer.front.type != Tok!")") {
      do {
        func.parameterTypes ~= new TypeExpr(parseExpression());
        if (isExtern)
          lexer.consume(Identifier);
        else
          func.parameterIdentifiers ~= expect(Identifier, "Expected parameter name");

      } while (lexer.consume(Tok!","));
    }
    expect(Tok!")", "Expected ')'");

    if (isExtern) {
      expect(Tok!"->", "Expected '->'");
      func.returnType = new TypeExpr(parseExpression());
    }
    return new TypeDeclStmt(func);
  }

  TypeDeclStmt parseModule(bool isExtern = false) {
    lexer.expect(Tok!"module", "Expected module");
    Token ident = expect(Identifier, "Expected identifier");
    expect(Tok!"{", "Expected '}'");

    auto mod = ModuleType.create(ident);
    StructDecl structDecl = new StructDecl(mod, ident);
    mod.decl = structDecl;
    structDecl.external = isExtern;

    while (lexer.front.type != Tok!"}") {
      if (lexer.front.type == Tok!"function") {
        MethodDecl method = parseMethod(structDecl);
        structDecl.define(method.name, method);
      } else {
        Decl field = parseField(structDecl);
        if (!field) break;
        structDecl.define(field.name, field);
        lexer.expect(Tok!";", "Expected ';'");
      }
    }
    expect(Tok!"}", "Expected '}'");

    //new NamedType(ident.value.idup, new ModuleType())
    return new TypeDeclStmt(structDecl);
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

  Stmt parseStatement() {
    switch (lexer.front.type) {
      case Tok!"import":
        return parseImport();
      case Tok!"extern":
        lexer.consume();
        if (lexer.front.type == Tok!"module")
          return parseModule(true);
        else {
          auto f = parseFunction(true);
          lexer.expect(Tok!";", "Expected ';'");
          return f;
        }
      case Tok!"module":
        return parseModule();
      case Tok!"function": {
        auto f = parseFunction();
        lexer.expect(Tok!";", "Expected ';'");
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
    auto prog = new Library([parseStatements()]);
    lexer.expect(EOF, "Expected end of file");
    return prog;
  }

  Context context;
}
