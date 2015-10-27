module duck.server;

import std.algorithm : remove;
import std.conv : to;
import std.socket : InternetAddress, Socket, SocketException, SocketSet, TcpSocket, SocketShutdown, SocketOption, SocketOptionLevel;
import std.stdio : writeln, writefln;
import core.time: dur;

struct Server {
	TcpSocket listener;
	Socket client;
	SocketSet socketSet;

	void stop() {
		if (listener) {
			writefln("Stop listening.");
			listener.shutdown(SocketShutdown.BOTH);
	        listener.close();
	        assert(!listener.isAlive);
	        listener = null;
	    }
	}

	void start(ushort port)
	{   
	    listener = new TcpSocket();
	    assert(listener.isAlive);
	    listener.blocking = false;
	    listener.bind(new InternetAddress(port));
	    listener.setOption(SocketOptionLevel.IP, SocketOption.REUSEADDR, true);
	    listener.listen(1);

	   	socketSet = new SocketSet(1);

	    writefln("Listening on port %d.", port);
	}

	void update() {
		if (client) {
			char[1024*16] buf;
			auto length = client.receive(buf[]);
			if (length == Socket.ERROR) {
				//writefln("Connection Error.");
			} 
			else if (length != 0) {
				writefln("Received %d bytes from %s: \"%s\"", length, client.remoteAddress().toString(), buf[0..length]);	
			}
			else {
                try
                {
                    // if the connection closed due to an error, remoteAddress() could fail
                    writefln("Connection from %s closed.", client.remoteAddress().toString());
                }
                catch (SocketException)
                {
                    writeln("Connection closed.");
                }
                client.shutdown(SocketShutdown.BOTH);
                client.close();
                client = null;
            }
        }

        if (!client) {
        	socketSet.reset();
        	socketSet.add(listener);
        	if (Socket.select(socketSet, null, null, dur!"seconds"(0)) > 0) {
	        	client = listener.accept();
	        	scope (failure) {
	        		writefln("Error accepting");
	        		if (client) {
	        			client.close();
	        			client = null;
	        		}
	        	}

	        	client.blocking = false;
	       
	            assert(client.isAlive);
	            assert(listener.isAlive);
	        }
        }
	}
}

