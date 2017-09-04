module duck.util.stack;

import std.traits: isSomeFunction;

struct Stack(T) {
  T[] items;

  this(T[] items) {
    this.items = items;
  }

  void push(T t) {
    assumeSafeAppend(items);
    items ~= t;
  }

  void pop() {
    items = items[0..$-1];
  }

  ref T top() {
    return items[$-1];
  }

  T find(alias test)() if (isSomeFunction!test) {
    for(int i = cast(int)(items.length)-1; i >= 0; --i) {
      auto item = items[i];
      if (test(item)) return item;
    }
    return T.init;
  }

  U find(U)() if (!isSomeFunction!U) {
    return cast(U) find!(function U(T item) => cast(U)item);
  }

  alias items this;
}
