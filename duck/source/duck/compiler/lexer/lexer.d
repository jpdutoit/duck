module duck.compiler.lexer.lexer;

import duck.compiler.buffer;
import duck.compiler.lexer.tokens;
import duck.compiler.input;
import duck.compiler.context;

enum LOOKAHEAD = 2;

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
  ref Token front() {
    return tokens[frontIndex];
  }

  @property
  ref Token back() {
    return tokens[(frontIndex + LOOKAHEAD - 1) % LOOKAHEAD];
  }

  Slice sliceFrom(Slice from) {
    return input.slice(from, last);
  }

  void expect(Token.Type type, string message) {
    if (!consume(type)) {
      context.error(front, "%s not '%s'", message, front.value);
      //auto msg = "(" ~ front.span.to!string ~ "): " ~ message ~ " not " ~ front.value.idup;
      //error(msg);
    }
  }

  Token peek(int N) {
    assert(N < LOOKAHEAD, "Can only lookahead max " ~ LOOKAHEAD);
    return tokens[(frontIndex + N) % LOOKAHEAD];
  }

  Token consume(Token.Type type) {
    if (front.type == type) {
      return consume();
    }
    return None;
  }

  Token consume() {
    Token old = front;
    popFront();
    return old;
  }

  void popFront() {
    last = front;
    frontIndex = (frontIndex + 1) % LOOKAHEAD;
    do {
      back = tokenizeNext();
    } while (back.isWhitespace);
  }

  private Token tokenizeNext() {
    auto saved = input.save();
    Token.Type tokenType;
    switch (input.front) {
      case '\t':
      case ' ': input.consume(); tokenType = Tok!" "; break;
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
          input.consume('\n');
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
          (input.front == '_'))
          input.consume();
        tokenType = Identifier;
        break;
      case '0':
      ..
      case '9':
        input.consume();
        while ((input.front >= '0' && input.front <= '9')) input.consume(1);
        if (input.front == '.') {
          input.consume();
          while ((input.front >= '0' && input.front <= '9')) input.consume(1);
        }
        tokenType = Number;
        break;
      case '.':
        input.consume();
        if (input.front >= '0' && input.front <= '9') {
          input.consume();
          while ((input.front >= '0' && input.front <= '9')) input.consume(1);
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
      auto type = token.value in reservedWords;
      if (type != null)
        token.type = *type;
    }

    return token;
  }
}
