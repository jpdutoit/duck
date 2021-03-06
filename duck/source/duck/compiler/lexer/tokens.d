module duck.compiler.lexer.tokens;

public import duck.compiler.lexer.token;
import duck.compiler.dbg;
import std.meta: staticIndexOf, AliasSeq;

enum TokenSpecial  = AliasSeq!(
  "__Number", "__String", "__Identifier", "__EOF", "__Comment", "__Unknown", "__Bool"
);
enum TokenReservedWords = AliasSeq!(
  "function", "module", "extern", "import", "struct", "distinct", "return", "constructor", "if", "else", "with", "@private", "@public", "@const", "@static", "@output", "true", "false", "alias", "and", "or"
);
enum TokenSymbols = AliasSeq!(
  " ", "\n",
  "!",
  "+", "-", "*", "/", "%",
  ">", "<", ">=", "<=", "==", "!=",
  ">>", "=>", "->",
  "+=", "=", ":=",
  ".", ",", ":", ";",
  "(", ")", "[", "]", "{", "}"
);

template Tok(string S) {
  static if (staticIndexOf!(S, TokenSpecial) >= 0) {
    enum Token.Type Tok = staticIndexOf!(S, TokenSpecial);
  }
  else static if (staticIndexOf!(S, TokenReservedWords) >= 0) {
    enum Token.Type Tok = staticIndexOf!(S, TokenReservedWords) + TokenSpecial.length;
  }
  else static if (staticIndexOf!(S, TokenSymbols) >= 0) {
    enum Token.Type Tok = staticIndexOf!(S, TokenSymbols) + TokenSpecial.length + TokenReservedWords.length;
  }
  else {
    static assert(0, "Token '" ~ S ~ "' not defined.");
  }
}

alias Number = Tok!"__Number";
alias StringLiteral = Tok!"__String";
alias Identifier = Tok!"__Identifier";
alias BoolLiteral = Tok!"__Bool";
alias EOF = Tok!"__EOF";
alias EOL = Tok!"\n";
alias Comment = Tok!"__Comment";
alias Unknown = Tok!"__Unknown";

enum None = Token();


immutable Token.Type[string] reservedWords;

alias WhitespaceFilter = immutable bool[Token.Type];
WhitespaceFilter multiline;
WhitespaceFilter singleline;
WhitespaceFilter includeWhitespace = null;

shared static this()
{
  multiline = [
    Tok!" ": true,
    EOL: true,
    Comment: true,
    Unknown: true
  ];
  singleline = [
    Tok!" ": true,
    Comment: true,
    Unknown: true
  ];

  reservedWords = [
    "function": Tok!"function",
    "module": Tok!"module",
    "extern": Tok!"extern",
    "import": Tok!"import",
    "struct": Tok!"struct",
    "return": Tok!"return",
    "constructor": Tok!"constructor",
    "if": Tok!"if",
    "else": Tok!"else",
    "with": Tok!"with",
    "@private": Tok!"@private",
    "@public": Tok!"@public",
    "@const": Tok!"@const",
    "@static": Tok!"@static",
    "@output": Tok!"@output",
    "alias": Tok!"alias",
    "distinct": Tok!"distinct",
    "true": BoolLiteral,
    "false": BoolLiteral,
    "and": Tok!"and",
    "or": Tok!"or"
  ];
}

@property
bool isWhitespace(Token token) {
  return token.type == Tok!" " || token.type == EOL || token.type == Comment || token.type == Unknown;
}

@property
bool isVisibilityAttribute(Token token)  {
  return (token.type == Tok!"@private") || (token.type == Tok!"@public");
}
@property
bool isStorageClassAttribute(Token token) {
  return (token.type == Tok!"@const");
}

@property
bool isMethodBindingAttribute(Token token) {
  return (token.type == Tok!"@static");
}

@property
bool isAttribute(Token token) {
  return token.isVisibilityAttribute || token.isStorageClassAttribute || token.isMethodBindingAttribute || token.type == Tok!"extern" || token.type == Tok!"@output";
}
