module duck.util.list;

interface LinkListItem(T) {
  T prev;
  T next;
}


mixin template List(T) {
  T first;
  T last;

  void insertBefore(T before, T after) {
    before.parent = this;
    before.prev = after.prev;
    before.next = after;
    if (before.prev)
      before.prev.next = before;
    else
      this.first = before;
    after.prev = before;
  }

  void prepend(T stmt) {
    stmt.parent = this;
    stmt.prev = null;
    stmt.next = this.first;
    if (stmt.next)
      stmt.next.prev = stmt;
    else
      this.last = stmt;
    this.first = stmt;
  }

  void insertAfter(T before, T after) {
    after.parent = this;
    after.prev = before;
    after.next = before.next;
    before.next = after;
    if (after.next)
      after.next.prev = after;
    else
      this.last = after;
  }

  void append(T stmt) {
    stmt.parent = this;
    stmt.prev = this.last;
    stmt.next = null;
    if (stmt.prev)
      stmt.prev.next = stmt;
    else
      this.first = stmt;
    this.last = stmt;
  }

  void replace(T old, T stmt) {
    if (old == stmt) return;
    stmt.parent = this;

    stmt.prev = old.prev;
    stmt.next = old.next;
    if (stmt.prev)
      stmt.prev.next = stmt;
    else
      this.first = stmt;
    if (stmt.next)
      stmt.next.prev = stmt;
    else
      this.last = stmt;
  }

  void remove(T old) {
    if (old.prev)
      old.prev.next = old.next;
    else
      first = old.next;
    if (old.next)
      old.next.prev = old.prev;
    else
      last = old.prev;
  }

  T[] array() {
    T[] arr;
    foreach(stmt; this) {
      arr ~= stmt;
    }
    return arr;
  }

  int opApply(scope int delegate(ref T) dg)
  {
    int result = 0;
    for (auto current = this.first; current;) {
      auto temp = current;
      result = dg(temp);
      if (temp != current) {
        if (temp)
          this.replace(current, temp);
        else
          this.remove(current);
      }
      if (result) break;
      current = current.next;
    }
    return result;
  }
}
