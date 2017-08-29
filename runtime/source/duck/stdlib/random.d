module duck.stdlib.random;

double uniform(double lo, double hi) {
  immutable next = randomGenerator.next();
  immutable range = hi-lo;
  return (cast(double)next / cast(double)(ulong.max) * range + lo);
}

private:

// Algorithm from: http://xoroshiro.di.unimi.it/xoroshiro128plus.c
struct Xoroshiro128 {
  ulong[2] state;

  // Initialize generator seeding with current time
  static Xoroshiro128 withCurrentTime() {
    import core.time: MonoTime;
    Xoroshiro128 gen;
    gen.state[0] = MonoTime.currTime.ticks;
    gen.state[1] = MonoTime.currTime.ticks * 113;
    gen.next(); // Burn the seed
    return gen;
  }

  // Get the next random number
  ulong next() {
    import core.bitop: rol;

  	immutable ulong s0 = state[0];
  	ulong s1 = state[1];
  	immutable ulong result = s0 + s1;

  	s1 ^= s0;
  	state[0] = rol(s0, 55) ^ s1 ^ (s1 << 14); // a, b
  	state[1] = rol(s1, 36); // c

  	return result;
  }
}

Xoroshiro128 randomGenerator;
static this() {
  randomGenerator = Xoroshiro128.withCurrentTime();
}
