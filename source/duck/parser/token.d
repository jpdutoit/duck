module duck.compiler.token;

alias String = const(char)[];

/*
	struct Type {
		this(string name) {
			this.name = name;
			this.id = name.hashOf();
		}
		string name;
		size_t id;

		alias id this;
	};
*/

struct Token {
	alias Type = size_t;
	Type type;

    bool opCast(T : bool)() const {
    	return type != 0;
    }

    this(Type type, String buffer, int start = 0, int end = 0) {
    	this.type = type;
    	this.buffer = buffer;
    	this.start = start;
    	this.end = end;
    }

    @property String value() {
    	return buffer[start..end];
    }

		alias value this;

		int lineNumber() {
			int line = 1;
			for (int i = 0; i < start; ++i) {
				if (buffer[i] == '\n') {
					line++;
				}
			}
			return line;
		}

	private:
		int start;
		int end;
		String buffer;
};

enum Token.Type Reserved(string A) = A.hashOf();
enum Token.Type Symbol(string A) = A.hashOf();
enum Token.Type Identifier = "Identifier".hashOf();
enum Token.Type Unknown =  "Unknown".hashOf();
//enum TypeIdentifier = "TypeIdentifier".hashOf();
enum Token.Type Number = "Number".hashOf();
enum Token.Type StringLiteral = "StringLiteral".hashOf();
enum Token.Type EOF = "EOF".hashOf();
enum Token.Type EOL = Symbol!("\n");
enum Token.Type Comment = "Comment".hashOf();
enum None = Token(0, null);
