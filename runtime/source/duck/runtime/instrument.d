module duck.runtime.instrument;

import duck.runtime.print;
import duck.stdlib.units;

int idCount = 0;
short instr_codes = 0;
short[size_t] codeForAddr;

void instrumentNextSample() {
	//return;
	//rawWrite3(cast(short)0);
}

short instrumentationCode(string id, void* address) {
	size_t addr = cast(size_t)address;

	short *b = addr in codeForAddr;
	if (!b) {
		codeForAddr[addr] = ++instr_codes;

		rawWrite3(cast(short)(-instr_codes));
		rawWrite3(cast(short)id.length);
		rawWrite2(id);
	}
	return codeForAddr[addr];
}

void instrument(T)(string id, void* address, T value) {
	throw new Error("Unsupported instrumentation type: " ~ T.stringof);
}

void instrument(T : float)(string id, void* address, T value) {
	rawWrite3(instrumentationCode(id, cast(void*)address));
	rawWrite3(value);
}

void instrument(T : double)(string id, void* address, T value) {
	rawWrite3(instrumentationCode(id, cast(void*)address));
	rawWrite3(cast(float)value);
}


void instrument(T : duration)(string id, void* address, T value) {
	rawWrite3(instrumentationCode(id, cast(void*)address));
	rawWrite3(cast(float)(value.samples));
}

void instrument(T : frequency)(string id, void* address, T value) {
	rawWrite3(instrumentationCode(id, cast(void*)address));
	rawWrite3(value.value);
}
