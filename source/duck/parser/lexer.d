module duck.compiler.lexer;

import duck.compiler.token;
import duck.compiler.input;

struct Lexer {
	Input input;
	Token front;

	this(String input) {
		this.input = Input(input);
		consume();
	}

	Token next() {
		return front;
	}

	void expect(Token.Type type, string message) {
		if (!consume(type)) {
			import std.conv : to;
			throw new Exception("(" ~ input.lineNumber().to!string ~ ") " ~ message ~ " not " ~ front.value.idup);
		}
	}

	Token consume(Token.Type type, bool includeWhiteSpace = true) {
		import std.stdio;
		writefln("lexer.consume %s %s", front.type, type);
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
			while (consume(Symbol!" ", false)
				|| consume(EOL, false) || consume(Comment, false)) {
			}
		}
		return old;
	}

	void popFront() {
		auto saved = input.save();
		Token.Type tokenType;
		switch (input.front) {
			case '\t':
			case ' ': input.consume(1); tokenType = Symbol!" "; break;
			case '\n': input.consume(1); tokenType = Symbol!"\n"; break;
			case ',': input.consume(1); tokenType = Symbol!","; break;
			case '%': input.consume(1); tokenType = Symbol!"%"; break;
			case '+':
				input.consume(1);
				if (input.consume('=')) {
					tokenType = Symbol!"+=";
				}
				else
					tokenType = Symbol!"+";
				break;
			case '-': input.consume(1); tokenType = Symbol!"-"; break;
			case '*':
				input.consume(1);
				if (input.consume('/')) {
					tokenType = Symbol!"*/";
				}
				else {
					tokenType = Symbol!"*";
				}
				break;
			case '(': input.consume(1); tokenType = Symbol!"("; break;
			case ')': input.consume(1); tokenType = Symbol!")"; break;
			case '[': input.consume(1); tokenType = Symbol!"["; break;
			case ']': input.consume(1); tokenType = Symbol!"]"; break;
			case '{': input.consume(1); tokenType = Symbol!"{"; break;
			case '}': input.consume(1); tokenType = Symbol!"}"; break;
			case ';': input.consume(1); tokenType = Symbol!";"; break;
			case '>':
				input.consume(1);
				if (input.consume('>')) { tokenType = Symbol!"=>"; break; }
				tokenType = Symbol!">";
				break;
			case '/':
				input.consume(1);
				if (input.consume('/')) {
					while (input.front && input.front != '\n') {
						input.consume(1);
					}
					input.consume('\n');
					tokenType = Comment;
					break;
				}
				else if (input.consume('*')) {
					while (front.type != Symbol!"*/" && front.type != EOF) {
						popFront();
					}
					if (front.type == Symbol!"*/") {
						popFront();
						return;
					}
				}
				else
					tokenType = Symbol!"/";
				break;
			case '"':
				input.consume(1);
				while (input.front && input.front != '\n' && input.front != '"') {
					// Skip escape codes
					if (input.front == '\\')
						input.consume(1);
					input.consume(1);
				}
				input.expect('"');
				tokenType = StringLiteral;
				break;
			case '=':
				input.consume(1);
				if (input.consume('>')) { tokenType = Symbol!"=>"; break; }
				if (input.consume('=')) { tokenType = Symbol!"=="; break; }
				tokenType = Symbol!"=";
				break;
			case 'a':
			..
			case 'z':
/*				input.consume(1);
				while ((input.front >= 'a' && input.front <= 'z') ||
					(input.front >= 'A' && input.front <= 'Z') ||
					(input.front >= '0' && input.front <= '9') ||
					(input.front == '_'))
					input.consume(1);
				tokenType = Identifier;
				break;*/
			case 'A':
			..
			case 'Z':
				input.consume(1);
				while ((input.front >= 'a' && input.front <= 'z') ||
					(input.front >= 'A' && input.front <= 'Z') ||
					(input.front >= '0' && input.front <= '9') ||
					(input.front == '_'))
					input.consume(1);
				tokenType = Identifier;
				break;
			case '0':
			..
			case '9':
				input.consume(1);
				while ((input.front >= '0' && input.front <= '9')) input.consume(1);
				if (input.front == '.') {
					input.consume(1);
					while ((input.front >= '0' && input.front <= '9')) input.consume(1);
				}
				tokenType = Number;
				break;
			case '.':
				input.consume(1);
				if (input.front >= '0' && input.front <= '9') {
					input.consume(1);
					while ((input.front >= '0' && input.front <= '9')) input.consume(1);
					tokenType = Number;
					break;
				}
				tokenType = Symbol!".";
				break;
			case 0:
				tokenType = EOF;
				break;
			default:
				input.consume(1);
				tokenType = Unknown;
				//throw new Exception(("Did not expect character: " ~ input.consume(1)).idup);
				break;
		}
		front = input.tokenSince(tokenType, saved);

		if (tokenType == Identifier) {
			auto str = front.value;
			if (str == "extern") front.type = Reserved!"extern";
			if (str == "generator") front.type = Reserved!"generator";
			if (str == "import") front.type = Reserved!"import";
		}
		import std.stdio;
		writefln("lexer.front %s %s", front.type, front.value);

		import std.stdio;
		//writefln("next %s", front);
	}
}
