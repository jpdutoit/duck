module duck.compiler.lexer.tokens;

public import duck.compiler.lexer.token;
import std.meta: staticIndexOf, AliasSeq;

enum TokenSpecial  = AliasSeq!(
  "__Number", "__String", "__Identifier", "__EOF", "__Comment", "__Unknown"
);
enum TokenReservedWords = AliasSeq!(
  "function", "module", "extern", "import", "struct", "return", "constructor"
);
enum TokenSymbols = AliasSeq!(
  " ", "\n",
  "!",
  "+", "-", "*", "/", "%",
  ">", "<", ">=", "<=", "==", "!=",
  ">>", "=>", "->",
  "+=", "=",
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
alias EOF = Tok!"__EOF";
alias EOL = Tok!"\n";
alias Comment = Tok!"__Comment";
alias Unknown = Tok!"__Unknown";

enum None = Token();


immutable Token.Type[string] reservedWords;
shared static this()
{
  reservedWords = [
    "function": Tok!"function",
    "module": Tok!"module",
    "extern": Tok!"extern",
    "import": Tok!"import",
    "struct": Tok!"struct",
    "return": Tok!"return",
    "constructor": Tok!"constructor"
  ];
}
