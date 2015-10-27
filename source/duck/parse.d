module duck.parse;

import std.string, std.stdio, std.array;

int tmpIndex = 0;

const(char)[] matchString(ref const(char)[] input) {
	if (input[0] == '"') {
		size_t index = 1;
		while (index < input.length && input[index] != '"') {
			if (input[index] == '\\')
				index++;
			index++;
		}
		if (input[index] == '"')
			return input.consume(index+1);
	}
	return input.consume(0);
}

const(char)[] matchParen(ref const(char)[] input) {
	const(char)[] work = input;
	if (work.length > 0 && work[0] == '(') {
		work.consume(1);
		int depth = 1;
		while (depth > 0 && work.length > 0) {
			//writefln("ww '%s'", work, depth);
			if (work[0] == '(') depth++;
			else if (work[0] == ')') depth--;
			else if (work[0] == '"') {
				auto string = work.matchString();
				if (string.length < 2) {
					return input.consume(0);
				}
				continue;
			}
			work.consume(1);
		}
		if (depth == 0)
			return input.consume(input.length-work.length);

	}
	return input.consume(0);
}


const(char)[] consume(ref const(char)[] input, size_t length)
{
	auto v = input[0 .. length];
	input = input[length .. $];
	return v;
}

const(char)[] parseOpen(ref const(char)[] input) {
	size_t index = 0;
	while (input[index] == ' ' && index < input.length) {
		index ++;
	}
	if (index < input.length && input[index] == '{') {
		return input.consume(index+1);
	}

	return input.consume(0);
}

const(char)[] parseIdentifier(ref const(char)[] input) {
	size_t index = 0;
	if (index < input.length && ((input[index] >= 'a' && input[index] <= 'z') ||
		(input[index] >= 'A' && input[index] <= 'Z'))) {
		index++;

		while (index < input.length && ((input[index] >= 'a' && input[index] <= 'z') ||
			(input[index] >= 'A' && input[index] <= 'Z') ||
			(input[index] >= '0' && input[index] <= '9') ||
			input[index] == '_')) {
			index++;
		}
		if (index > 0) {
			return input.consume(index);
		}
	}
	return null;
}

const(char)[] parseWhitespace(ref const(char)[] input) {
	size_t index = 0;
	while (index < input.length && (input[index] == ' ' || input[index] == '\t')) {
		index++;
	}
	return input.consume(index);
}

struct InlineDecl {
	const(char)[] pre;
	const(char)[] type;
	const(char)[] name;
	const(char)[] args;
}

InlineDecl parseInlineDecl(ref const(char)[] input) {
	const(char)[] work = input;

	size_t index = 0;
	while (index < work.length && work[index] != '\n' && !((input[index] >= 'a' && input[index] <= 'z') ||
		(input[index] >= 'A' && input[index] <= 'Z')) ) {
		index++;
	}
	if (index == work.length) return InlineDecl();

	InlineDecl decl;
	int adjust = 0;
	decl.pre = work.consume(index);
	decl.type = work.parseIdentifier();
	if (decl.type.length == 0 || !(decl.type[0] >= 'A' && decl.type[0] <= 'Z')) return InlineDecl();
	auto ws = work.parseWhitespace();
	decl.name = work.parseIdentifier();
	decl.args = work.matchParen();

	//auto tmp = work;
	//tmp.parseWhitespace();
	//if (tmp[0] == ';') return InlineDecl();

	if (work.parseOpen().length > 0) {
		return InlineDecl();
	}

	if (decl.name.length == 0) {
		decl.name = format("a%s%d", decl.type, tmpIndex++);
		adjust -= decl.name.length;
		//return InlineDecl();
	}

	input.consume(decl.pre.length + decl.type.length + ws.length + decl.name.length + decl.args.length + adjust);
	return decl;
}

//alias trigger = ctRegex!(r"^([^\n]*?)(\w+) +(\w+)\s*(?!\w+)");
//alias open = ctRegex!(r"^\s*\{");

const(char)[] parse(const(char)[] input) {
	const(char)[] output;
	const(char)[] waiting;
	while (input.length > 0) {
		if (input[0] == '\n') {
			auto tmp = waiting;
			tmp.parseWhitespace();
			tmp.parseIdentifier();

			if (tmp.length > 0 && tmp[0] == ';') {
				tmp.consume(1);
				waiting = tmp;
			}

			output ~= waiting ~ "\n";
			input.consume(cast(ulong)1);
			waiting.length = 0;
			continue;
		}

		auto save = input;
		auto c = input.parseInlineDecl();
		if (c.type.length) {
			//auto paren = input.matchParen();
			//if (input.parseOpen().length == 0) {
			output ~= c.type ~ " " ~ c.name ~ (c.args.length > 0 ? " = " ~ c.type ~ c.args : "") ~ ";";
			waiting ~= c.pre ~ c.name;
			//index += c.hit.length + paren.length;
			continue;
		}
		waiting ~= input[0..1];
		input.consume(1);
	}
/*
	for (size_t index = 0; index < input.length;) {
		if (input[index] == '\n') {
			output ~= waiting ~ "\n";
			waiting.length = 0;
			index++;
			continue;
		}

		auto c = input[index..$].matchFirst(trigger);
		if (c.hit.length) {
			auto paren = matchParen(input[index + c.hit.length .. $]);
			writeln(paren);
			if (parseOpen(input[index + c.hit.length + paren.length .. $]).length == 0) {
				output ~= c.pre ~ c[2] ~ " " ~ c[3] ~ (paren.length > 0 ? " = " ~ c[2] ~ paren : "") ~ ";";
				waiting ~= c[1] ~ c[3];
				index += c.hit.length + paren.length;
			}
		}

		waiting ~= input[index..index+1];
		index++;
	}*/
	return output;
}

const(char)[] compile(const(char)[] input) {
	
	auto s = 
	q{import duck, std.stdio, duck.global, duck.types;} 
	~ "void start() { " ~ parse(input) ~ "\n}" ~ 
	q{
		void main() { 
			Duck(&start);
		}
	};
	//auto s = output.join("");
	//auto app = appender!string();
	//doit("test.d", cast(ubyte[])(input.dup), app);
	//writefln("%s => %s", input, s);
	return s;
}

