module duck.plugin.portaudio;

import duck.runtime, duck.stdlib;

import deimos.portaudio;
import duck.runtime.global;

struct Audio
{
  PaStream* stream;

  long framesToWriteWithoutBlocking() {
    return Pa_GetStreamWriteAvailable(stream);
  }

  void write(void* buffer) {
    //writefln("%s", framesToWriteWithoutBlocking());
    PaError err = Pa_WriteStream( stream, buffer, 64);
    if (err != paNoError) {
      print("write.error ");
      print(Pa_GetErrorText(err));
      print("\n");
    }
  }

  void read(void *buffer) {
    PaError err = Pa_ReadStream( stream, buffer, 64 );
    if (err != paNoError) {
      print("read.error ");
      print(Pa_GetErrorText(err));
      print("\n");

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

      print("done.error ");
      print(Pa_GetErrorText(err));
      print("\n");
  }

  void init() {
    PaError err;
    if ((err = Pa_Initialize()) != paNoError
      || (err = Pa_OpenDefaultStream(&stream,
                                    1,
                                    2,
                                    paFloat32,
                                    SAMPLE_RATE.value,
                                    64, //paFramesPerBufferUnspecified,
                                    null, //&sawtooth,
                                    null)) != paNoError
      || (err = Pa_StartStream(stream)) != paNoError)
    {
      print("Error opening audio stream: ");
      print(Pa_GetErrorText(err));
      print("\n");
      halt();
      return;
    }

    const PaStreamInfo* info = Pa_GetStreamInfo(stream);
    /*
    print("Audio sample rate ");
    print(info.sampleRate);
    print("\n");
    */
    if (SAMPLE_RATE.value != info.sampleRate) {
      print("Requested sample rate (");
      print(SAMPLE_RATE.value);
      print("not available for audio output.");
      print("\n");
      halt();
    }
    //
    now.samples = Pa_GetStreamTime(stream) * SAMPLE_RATE.value;
    //writefln("Start time: %s", now.samples); stdout.flush();
    //Pa_Sleep(1000 * 1000);
  }

};

Audio audio;
