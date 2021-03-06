module duck.runtime;

public import duck.runtime.scheduler.single;
public import duck.runtime.model;
public import duck.runtime.entry;
public import duck.runtime.global;
public import duck.runtime.print;

version (USE_INSTRUMENTATION) {
  public import duck.runtime.instrument;
}

public import core.math;
public import core.stdc.math: ceilf, floorf, roundf, powf, fabs, log2f;
alias abs = fabs;
alias log2 = log2f;

int modulus(int i, int M) nothrow {
  return ((i % M) + M) % M;
}
float modulus(float i, float M) nothrow {
  return ((i % M) + M) % M;
}
int remainder(int i, int M) nothrow {
  return i % M;
}
float remainder(float i, float M) nothrow {
  return i % M;
}


private struct FixedSizeBufferFreeList(int size, int ChunkSize = 64, int Capacity = 1024) {
  __gshared static void*[Capacity] available = void;
  __gshared static size_t length = 0;

  static void* claim() {
    if (length == 0) {
      import core.stdc.stdlib: malloc;
      void *ptr = malloc(ChunkSize * size);
      for (auto i = 0; i < ChunkSize; ++i)
        available[i] = ptr + (i * size);
      length = ChunkSize;
    }
    return available[--length];
  }

  static void release(void* ptr) {
    if (length < Capacity) {
      available[length++] = ptr;
    } else {
      // Leak the memory, whatever...
    }
  }
}

private struct RawBuffer(int ChunkSize) {
  alias FreeList = FixedSizeBufferFreeList!ChunkSize;
  void*[] parts;
  int capacity;
  int length;

  auto opIndex(size_t index) {
    size_t part = index / ChunkSize;
    size_t i = index % ChunkSize;
    return (parts[part] + i);
  }

  package void resize(int newLength) {
    if (newLength == length) return;
    if (newLength < 1) newLength = 1;
    if (newLength > 1024_000_000) newLength = 1024_000_000;
    length = newLength;
    if (newLength > capacity) {
      auto partsToAdd = (newLength / ChunkSize) + (newLength % ChunkSize != 0) - parts.length;
      capacity += partsToAdd * ChunkSize;
      assumeSafeAppend(parts);
      parts.length += partsToAdd;
      for (auto i = partsToAdd; i > 0; --i) {
        parts[parts.length - i] = FreeList.claim();
      }
    }
  }
}

struct TypedBuffer(T) {
  static auto alloc() {
    return TypedBuffer.init;
  }

  RawBuffer!65536 _buffer;
  auto ref opIndex(int index) nothrow {
    index = modulus(index, this.length);
    return *(cast(T*)_buffer[index * T.sizeof]);
  }

  T get(int index) nothrow {
    index = modulus(index, this.length);
    return *(cast(T*)_buffer[index * T.sizeof]);
  }

  void set(int index, T value) nothrow {
    index = modulus(index, this.length);
    *(cast(T*)_buffer[index * T.sizeof]) = value;
  }

  void resize(int newLength) nothrow {
    auto oldLength = length;
    if (newLength < 1) newLength = 1;
    _buffer.resize(newLength * cast(int)T.sizeof);
    for (auto i = oldLength; i < length; ++i)
      this[i] = 0;
  }

  int length() nothrow {
    return cast(int)(_buffer.length / T.sizeof);
  }

  auto length(int newLength) nothrow {
    resize(newLength);
  }

  auto length(float floatLength) nothrow {
    resize(cast(int)(floatLength + 0.5));
  }
}

alias SampleBuffer_ = TypedBuffer!float;

version(USE_PORT_AUDIO) {
  public import duck.plugin.portaudio;
}
