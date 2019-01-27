module duck.compiler.lexer.lexer;

import duck.compiler.buffer;
import duck.compiler.lexer.tokens;
import duck.compiler.input;
import duck.compiler.context;
import std.stdio: writeln, stderr;

enum LOOKAHEAD = 128;

struct Lexer {
  Input input;
  Token last;
  Token[LOOKAHEAD] tokens;
  Context context;

  uint frontIndex = 0;

  this(Context context, Buffer input) {
    this.input = Input(input);
    this.context = context;
    for (int i = 0; i < LOOKAHEAD; ++i) consume();
  }

  @property
  ref Token front(WhitespaceFilter filter = multiline) {
    for (int i = 0; i < LOOKAHEAD; ++i) {
      //stderr.writeln(i, " ", peek(i), " ", peek(i).type, " ", !(peek(i).type in filter));
      if (!(peek(i).type in filter)) return peek(i);
    }
    return tokens[frontIndex];
  }

  @property
  ref Token back() {
    return tokens[(frontIndex + LOOKAHEAD - 1) % LOOKAHEAD];
  }

  Slice sliceFrom(Slice from) {
    return input.slice(from, last);
  }

  void expect(Token.Type type, string message, WhitespaceFilter filter = multiline) {
    if (!consume(type, filter)) {
      context.error(front, "%s not '%s'", message, front.value);
      //auto msg = "(" ~ front.span.to!string ~ "): " ~ message ~ " not " ~ front.value.idup;
      //error(msg);
    }
  }

  ref Token peek(int N) {
    assert(N < LOOKAHEAD, "Can only lookahead max " ~ LOOKAHEAD);
    return tokens[(frontIndex + N) % LOOKAHEAD];
  }

  ref Token peek(int N, WhitespaceFilter filter) {
    assert(N < LOOKAHEAD, "Can only lookahead max " ~ LOOKAHEAD);
    for (int i = 0; i < LOOKAHEAD - N; ++i) {
      //stderr.writeln(i, " ", peek(i), " ", peek(i).type, " ", !(peek(i).type in filter));
      if (!(peek(i).type in filter)) {
        if (N == 0) return tokens[(frontIndex + i + N) % LOOKAHEAD];
        N--;
      }
    }
    return tokens[(frontIndex + N) % LOOKAHEAD];
  }

  Token consume(Token.Type type, WhitespaceFilter filter = multiline) {
    //stderr.writeln("Want to consume ", type, " have ", this.front(filter).type);
    if (this.front(filter).type == type) {
      return this.consume(filter);
    }
    return None;
  }

  Token consume(Token until) {
    while (peek(0) != until) {
      popFront();
    }
    popFront();
    return until;
  }

  Token consume(WhitespaceFilter filter = multiline) {
    while (peek(0).type in filter) {
      popFront();
    }
    Token old = peek(0);

    popFront();
    //stderr.writeln("Consume ", old, " ", old.type, ", Next: ", front.type);

    return old;
  }

  void popFront() {
    last = front;
    frontIndex = (frontIndex + 1) % LOOKAHEAD;
    back = tokenizeNext();
  }

  private Token tokenizeNext() {
    auto saved = input.save();
    Token.Type tokenType;
    switch (input.front) {
      case '\t':
      case ' ':
        while (input.consume(' ') || input.consume('\t')) {
          // Do nothing
        }
        tokenType = Tok!" ";
        break;
      case '\n': input.consume(); tokenType = Tok!"\n"; break;
      case ',': input.consume(); tokenType = Tok!","; break;
      case ':':
        input.consume();
        if (input.consume('=')) {
          tokenType = Tok!":=";
        } else {
          tokenType = Tok!":";
        }
        break;
      case '%': input.consume(); tokenType = Tok!"%"; break;
      case '+':
        input.consume();
        if (input.consume('=')) {
          tokenType = Tok!"+=";
        }
        else
          tokenType = Tok!"+";
        break;
      case '-':
        input.consume();
        if (input.consume('>')) {
          tokenType = Tok!"->";
          break;
        }
        tokenType = Tok!"-";
        break;
      case '*':
        input.consume();
        tokenType = Tok!"*";
        break;
      case '!': {
        input.consume();
        if (input.consume('=')) {
          tokenType = Tok!"!=";
          break;
        }
        tokenType = Tok!"!";
        break;
      }
      case '(': input.consume(); tokenType = Tok!"("; break;
      case ')': input.consume(); tokenType = Tok!")"; break;
      case '[': input.consume(); tokenType = Tok!"["; break;
      case ']': input.consume(); tokenType = Tok!"]"; break;
      case '{': input.consume(); tokenType = Tok!"{"; break;
      case '}': input.consume(); tokenType = Tok!"}"; break;
      case ';': input.consume(); tokenType = Tok!";"; break;
      case '<':
        input.consume();
        if (input.consume('=')) {
          tokenType = Tok!"<="; break;
        }
        tokenType = Tok!"<";
        break;
      case '>':
        input.consume();
        if (input.consume('>')) {
          tokenType = Tok!">>"; break;
        }
        if (input.consume('=')) {
          tokenType = Tok!">="; break;
        }
        tokenType = Tok!">";
        break;
      case '/':
        input.consume();
        if (input.consume('/')) {
          while (input.front && input.front != '\n') {
            input.consume();
          }
          tokenType = Comment;
          break;
        }
        else if (input.consume('*')) {
          int depth = 1;
          while (input.front && depth > 0) {
            if (input.consume('/')) {
              if (input.consume('*')) depth++;
            }
            else if (input.consume('*')) {
              if (input.consume('/')) depth--;
            }
            else input.consume();
          }
          if (depth != 0) {
            context.error(input.tokenSince(tokenType, saved), "Unterminated comment");
          }
          tokenType = Comment;
          /+
          while (front.type != Tok!"*/" && front.type != EOF) {
            popFront();
          }
          if (front.type == Tok!"*/") {
            popFront();
            return;
          }+/
        }
        else
          tokenType = Tok!"/";
        break;
      case '"':
        input.consume();
        while (input.front && input.front != '\n' && input.front != '"') {
          // Skip escape codes
          if (input.front == '\\')
            input.consume();
          input.consume();
        }
        if (!input.consume('"')) {
          context.error(input.tokenSince(tokenType, saved), "Unterminated string");
        }
        tokenType = StringLiteral;
        break;
      case '=':
        input.consume();
        if (input.consume('>')) {
          tokenType = Tok!"=>";
        }
        else if (input.consume('=')) {
          tokenType = Tok!"==";
        }
        else {
          tokenType = Tok!"=";
        }
        break;
      case '@':
      case 'a':
      ..
      case 'z':
      case 'A':
      ..
      case 'Z':
        input.consume();
        while ((input.front >= 'a' && input.front <= 'z') ||
          (input.front >= 'A' && input.front <= 'Z') ||
          (input.front >= '0' && input.front <= '9') ||
          (input.front == '_') || (input.front >= 128))
          input.consume();
        tokenType = Identifier;
        break;
      case '0':
      ..
      case '9':
        input.consume();
        while ((input.front >= '0' && input.front <= '9')) input.consume();
        if (input.front == '.') {
          input.consume();
          while ((input.front >= '0' && input.front <= '9')) input.consume();
        }
        tokenType = Number;
        break;
      case '.':
        input.consume();
        if (input.front >= '0' && input.front <= '9') {
          input.consume();
          while ((input.front >= '0' && input.front <= '9')) input.consume();
          tokenType = Number;
          break;
        }
        tokenType = Tok!".";
        break;
      case 0:
        tokenType = EOF;
        break;
      default:
        input.consume();
        tokenType = Unknown;
        Token token = input.tokenSince(tokenType, saved);
        context.error(token, "Unexpected character '%s'", token.value);
        return token;
    }
    Token token = input.tokenSince(tokenType, saved);

    if (tokenType == Identifier) {
      if (auto type = token.value in reservedWords) {
        token.type = *type;
      } else if (token.value[0] == '@') {
        context.error(token, "Invalid attribute");
        token.type = Unknown;
      }
    }

    return token;
  }
}
