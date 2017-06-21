module duck.util.stack;

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

  alias items this;
}
