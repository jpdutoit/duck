module duck.stdlib;

public import duck.runtime;

import duck.stdlib.units;

__gshared frequency SAMPLE_RATE = 44100.hz;

public import duck.stdlib.scales;
public import duck.stdlib.ugens;
public import duck.stdlib.units;

void assertEquals(float a, float b, string file = __FILE__, int line = __LINE__) {
  if (a != b) {
    print(file);
    print("(");
    print(line);
    print("): Assertion failed: ");
    print(a);
    print(" != ");
    print(b);
    print("\n");
  }
  //assert(a == b);
}
