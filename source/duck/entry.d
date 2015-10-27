module duck.entry;
import duck;

int Duck(void function() fn) {
	import std.stdio : writeln, stdout;

	stdout.flush();
	//Graphiti.instance.init("test", false);
	audio.init();
	spork(fn);
	Scheduler.run();
	//Graphiti.instance.close();
	return 0;
}