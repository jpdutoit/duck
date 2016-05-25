module duck.compiler.lexer.lexer;

import duck.compiler.buffer;
import duck.compiler.lexer.tokens;
import duck.compiler.input;
import duck.compiler.context;

struct Lexer {
  Input input;
  Token front;
  Context context;

  this(Context context, Buffer input) {
    this.input = Input(input);
    this.context = context;
    consume();
  }

  void expect(Token.Type type, string message) {
    if (!consume(type)) {
      context.error(front, "%s not '%s'", message, front.value);
      //auto msg = "(" ~ front.span.to!string ~ "): " ~ message ~ " not " ~ front.value.idup;
      //error(msg);
    }
  }

  Token consume(Token.Type type, bool includeWhiteSpace = true) {
    import std.stdio;
    if (front.type == type) {
      return consume(includeWhiteSpace);
    }
    return None;
  }

  Token consume(bool includeWhiteSpace = true) {
    Token old = front;
    popFront();

    if (includeWhiteSpace) {
      import std.stdio;
      while (consume(Tok!" ", false)
        || consume(EOL, false) || consume(Comment, false) || consume(Unknown, false)) {
      }
    }
    return old;
  }

  void popFront() {
    auto saved = input.save();
    Token.Type tokenType;
    switch (input.front) {
      case '\t':
      case ' ': input.consume(); tokenType = Tok!" "; break;
      case '\n': input.consume(); tokenType = Tok!"\n"; break;
      case ',': input.consume(); tokenType = Tok!","; break;
      case ':': input.consume(); tokenType = Tok!":"; break;
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
      case '(': input.consume(); tokenType = Tok!"("; break;
      case ')': input.consume(); tokenType = Tok!")"; break;
      case '[': input.consume(); tokenType = Tok!"["; break;
      case ']': input.consume(); tokenType = Tok!"]"; break;
      case '{': input.consume(); tokenType = Tok!"{"; break;
      case '}': input.consume(); tokenType = Tok!"}"; break;
      case ';': input.consume(); tokenType = Tok!";"; break;
      case '>':
        input.consume();
        if (input.consume('>')) {
          tokenType = Tok!">>"; break;
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
        front = input.tokenSince(tokenType, saved);
        context.error(front, "Unexpected character '%s'", front.value);
        return;
    }
    front = input.tokenSince(tokenType, saved);

    if (tokenType == Identifier) {
      auto str = front.value;
      if (str == "function") front.type = Tok!"function";
      if (str == "extern") front.type = Tok!"extern";
      if (str == "module") front.type = Tok!"module";
      if (str == "struct") front.type = Tok!"struct";
      if (str == "import") front.type = Tok!"import";
    }
  }
}
