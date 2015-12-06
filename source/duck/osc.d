
module duck.osc;

import core.sys.posix.unistd;
import core.sys.posix.sys.socket;
import core.sys.posix.fcntl;
import core.sys.posix.netdb;
import core.stdc.string;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.errno;
//import std.bitmanip;
import duck.runtime;

OSCServer oscServer;
//debug = OSC;

private uint swapEndianImpl(uint val) @trusted pure nothrow @nogc
{
    import core.bitop: bswap;
    return bswap(val);
}

private ulong swapEndianImpl(ulong val) @trusted pure nothrow @nogc
{
    import core.bitop: bswap;
    immutable ulong res = bswap(cast(uint)val);
    return res << 32 | bswap(cast(uint)(val >> 32));
}

struct OSCMessage {
  enum MAX_ARGS = 10;
  string target;
  string types;
  ubyte[][] arguments;
/*  string toString() {
    return "";

    //return format("%s %s", target, types);
  }*/

  void read(T)(int i, T* target) if (is(T:double) || is(T:float)) {
    if (i >= types.length) {
      *target = 0;
      return;
    }
     switch (types[i]) {
        case 'f': *target = _getFloat(i); return;
        case 'd': *target = _getDouble(i); return;
        default: break;
    }
  }

  float _getFloat(ulong i) {
    return *(cast(float*)arguments[i].ptr);
  }

  double _getDouble(ulong i) {
    return *(cast(double*)arguments[i].ptr);
  }
}

class OSCServer {
  enum MAX_QUEUE_SIZE = 50;
  OSCMessage messages[MAX_QUEUE_SIZE];
  int messagesLength;

  enum MAXBUFLEN = 16384;

  this() {
  }

  int sockfd;
  addrinfo hints;
  addrinfo* servinfo;
  addrinfo *p;
  int rv;

  sockaddr_storage their_addr;
  char buf2[MAXBUFLEN];

  socklen_t addr_len;
  char s[INET6_ADDRSTRLEN];

  void start(int port) {

      char[10] portString;
      import core.stdc.stdio;
      snprintf(portString.ptr, 10, "%d", port);

      memset(&hints, 0, hints.sizeof);
      hints.ai_family = AF_UNSPEC; // set to AF_INET to force IPv4
      hints.ai_socktype = SOCK_DGRAM;
      hints.ai_flags = AI_PASSIVE; // use my IP

      if ((rv = getaddrinfo(null, portString.ptr, &hints, &servinfo)) != 0) {
          import core.stdc.stdio;
          stderr.fprintf("getaddrinfo: %s\n", gai_strerror(rv));
          return;
      }

      // loop through all the results and bind to the first we can
      for(p = servinfo; p != null; p = p.ai_next) {
          if ((sockfd = socket(p.ai_family, p.ai_socktype,
                  p.ai_protocol)) == -1) {
              perror("listener: socket");
              continue;
          }

          fcntl(sockfd, F_SETFL, O_NONBLOCK);
          if (bind(sockfd, p.ai_addr, p.ai_addrlen) == -1) {
              close();
              perror("listener: bind");
              continue;
          }



          break;
      }

      if (p == null) {
          print("listener: failed to bind socket\n");
          close();
          return;
      }

      freeaddrinfo(servinfo);

      debug(duck_osc) print("listener: waiting to recvfrom...\n");
      addr_len = their_addr.sizeof;
  }



  //#define MAXBUFLEN 100

  // get sockaddr, IPv4 or IPv6:
  void *get_in_addr(sockaddr *sa)
  {
      if (sa.sa_family == AF_INET) {
          return &((cast(sockaddr_in*)sa).sin_addr);
      }

      return &((cast(sockaddr_in6*)sa).sin6_addr);
  }

  void close()
  {
      .close(sockfd);
  }

  int index;
  long length;

  string readString(void[] buf, ref int index) {
      int start = index;
      for (; index < length; ++index) {

          if (buf2[index] == 0) {
              break;
          }
          //writefln("%d", buf2[index]);
      }

      auto s = cast(string)buf[start..index];

      index++;
      while (index % 4 != 0) index++;
      return s;
  }

  OSCMessage *get(string target) {
    //for (int i = cast(int)messages.length-1; i >= 0; --i) {
    if (messagesLength > 0)
    for (int i = messagesLength - 1; i >= 0; --i) {
      float f;
      messages[i].read(0, &f);
      debug(OSC) print("get %s %s/%s %s %f", target, i, messagesLength, messages[i].target, f);
      if (messages[i].target == target) {

        return &messages[i];
      }
    }
    return null;
  }

  void receiveAll()
  {
    int bufRemaining = MAXBUFLEN - 1;
    void *buf = buf2.ptr;

    messagesLength = 0;

    for (int messageIndex = 0; messageIndex < MAX_QUEUE_SIZE; ++messageIndex) {

      if ((length = recvfrom(sockfd, buf, bufRemaining, 0,
          cast(sockaddr *)&their_addr, &addr_len)) == -1) {
          return;
      }

      void[] buffer = buf[0..length];
      buf += length;
      bufRemaining -= length;
      messagesLength++;




      int index = 0;

      OSCMessage *message = &messages[messageIndex];

      // Read message target
      message.target = readString(buffer, index);
      debug(OSC) print("%s", message.target);

      // Read arguments types
      auto types = message.types = readString(buffer, index)[1..$];

      // Parse arguments
      assumeSafeAppend(message.arguments);
      message.arguments.length = types.length;


      void swapEndian(T)() {
        static if (is(T:float)) {
          uint t = swapEndianImpl(*cast(uint*)(&buffer[index]));
          *cast(T*)(&buffer[index]) = *(cast(T*)(&t));
        }
        else static if (is(T:double)) {
          ulong t = swapEndianImpl(*cast(ulong*)(&buffer[index]));
          *cast(T*)(&buffer[index]) = *(cast(T*)(&t));
        }
        index += T.sizeof;
      }


      /*void fixEndian(T)() {
         import core.sys.posix.arpa.inet;

         *cast(T*)(&buffer[index]) = bigEndianToNative!T(*cast(ubyte[T.sizeof]*)(&buffer[index]));
         index += T.sizeof;
      }*/
      for (int i = 0; i < types.length; ++i) {
          switch (types[i]) {
              case 'f':
                  message.arguments[i] = cast(ubyte[])buffer[index..index+4];
                  swapEndian!float();
                  debug(OSC) print("    float %s", message._getFloat(i));
                  break;
              case 'd':
                  message.arguments[i] = cast(ubyte[])buffer[index..index+8];
                  swapEndian!double();
                  debug(OSC) print("    double %s", message._getDouble(i));
                  break;
              default:
                  print("    Type not supported: %s", types[i]);
                  exit(2);
          }
      }
    }
  }
}
