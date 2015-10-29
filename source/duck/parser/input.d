module duck.compiler.input;

import duck.compiler.token;

struct Input {
	String text;
	int index = 0;
	dchar front;

	void popFront() {
		consume(1);
	}

	@property bool empty() {
		return index >= text.length;
	}

	this(String text) {
		this.text = text;
		this.text = this.text ~ '\0';
		consume(0);
	}

	int lineNumber() {
		int line = 1;
		for (int i = 0; i < index; ++i) {
			if (text[i] == '\n') {
				line++;
			}
		}
		return line;
	}


	String consume(int howMuch = 1) {
		String a = text[index..index+howMuch];
		index += howMuch;
		front = text[index];
		return a;
	}

	void expect(char character) {
		if (!consume(character)) {
			throw new Exception("Expected " ~ character);
		}
	}

	bool consume(char character) {
		return consume(cast(dchar)character);
	}
	bool consume(dchar character) {
		if (front == character) {
			consume(1);
			return true;
		}
		else return false;
	}

	Token tokenSince(Token.Type type, ref Input input) {
		return Token(type, this.text, input.index, index);
	}

	auto save() {
		Input input;
		input.text = text;
		input.index = index;
		input.front = front;
		return input;
	}
};
