module duck.stdlib.scales;

struct Scale {
	static ubyte[] Major = [0, 2, 4, 5, 7, 9, 11];
	static ubyte[] Minor = [0, 2, 3, 5, 7, 8, 10];
	static ubyte[] Pentatonic = [0, 2, 4, 7, 9];
	static ubyte[] Indian = [0, 1, 1, 4, 5, 8, 10];
	static ubyte[] Turkish = [0, 1, 3, 5, 7, 10, 11];
	static ubyte[] Chromatic = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
	static ubyte[] Blues = [0, 2, 3, 4, 5, 7, 9, 10, 11];
}
