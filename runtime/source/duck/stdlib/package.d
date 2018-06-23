module duck.stdlib;

public import duck.runtime;

import duck.stdlib.units;

public import duck.stdlib.scales;
public import duck.stdlib.ugens;
public import duck.stdlib.units;
public import duck.stdlib.random;

void assertEquals(T)(T a, T b, string file = __FILE__, int line = __LINE__) nothrow {
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
