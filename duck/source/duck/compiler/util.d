module duck.compiler.util;

mixin template ArrayWrapper(T, alias elements) {
  int opApply(int delegate(ref T) dg)
  {
    int result = 0;
    for (int i = 0; i < elements.length; i++)
    {
      result = dg(elements[i]);
      if (result)
        break;
    }
    return result;
  }

  int opApply(int delegate(size_t index, ref T) dg)
  {
    int result = 0;
    for (int i = 0; i < elements.length; i++)
    {
      result = dg(i, elements[i]);
      if (result)
        break;
    }
    return result;
  }

  ref T opIndex(size_t index) {
    return elements[index];
  }

  size_t length() {
    return elements.length;
  }
}
