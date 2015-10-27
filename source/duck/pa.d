module duck.pa;

import duck.scheduler;

import deimos.portaudio;
import std.stdio;
import duck.global;

struct Audio
{
  PaStream* stream;
  
  long framesToWriteWithoutBlocking() {
    return Pa_GetStreamWriteAvailable(stream);
  }

  void write(void* buffer) {
    import std.string : fromStringz;
    //writefln("%s", framesToWriteWithoutBlocking());
    PaError err = Pa_WriteStream( stream, buffer, 64); 
    if (err != paNoError) {
      stderr.write("write.error ");
      stderr.writeln(Pa_GetErrorText(err).fromStringz);
    }
  }

  void read(void *buffer) {
    import std.string : fromStringz;
    PaError err = Pa_ReadStream( stream, buffer, 64 );    
    if (err != paNoError) {
      stderr.write("read.error ");
      stderr.writeln(Pa_GetErrorText(err).fromStringz);

    }
  }

  void done() {
    if (!stream)
      return;

    PaError err;

    if ((err = Pa_StopStream(stream)) != paNoError) goto Lerror;
    if ((err = Pa_CloseStream(stream)) != paNoError) goto Lerror;
    if ((err = Pa_Terminate()) != paNoError) goto Lerror;

    return;

   Lerror:
      import std.string : fromStringz;
      stderr.write("done.error ");
      stderr.writeln(Pa_GetErrorText(err).fromStringz);
  }

  void init() {
    PaError err;
    if ((err = Pa_Initialize()) != paNoError 
      || (err = Pa_OpenDefaultStream(&stream,
                                    1,
                                    2,
                                    paFloat32,
                                    SAMPLE_RATE,
                                    64, //paFramesPerBufferUnspecified,
                                    null, //&sawtooth,
                                    null)) != paNoError 
      || (err = Pa_StartStream(stream)) != paNoError) 
    {
      import std.string : fromStringz;
      stderr.write("init.error ");
      stderr.writeln(Pa_GetErrorText(err).fromStringz);
      return;
    }

    
    //
    now.samples = Pa_GetStreamTime(stream) * SAMPLE_RATE;
    writefln("Start time: %s", now.samples); stdout.flush();
    //Pa_Sleep(1000 * 1000);

    
  }

};

Audio audio;

