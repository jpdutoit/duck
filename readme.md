# Duck

A realtime audio synthesis language. This is still at the pre-alpha stage. Everything can and probably will change.


Note: Currently only supports Mac OS.

## Prerequisites

### Compiler:
- [DMD](https://dlang.org/download.html) v2.077.1 or newer
- [DUB](https://code.dlang.org)

### Editor:
- [NPM](https://www.npmjs.com/) v5 or newer
- [Node.js](https://nodejs.org)


## Building and running the compiler

Building the compiler:
```
./build.sh
```

Try it out:
```
bin/duck -- "hz(440 + 220 * (8hz >> SinOsc)) >> SinOsc >> DAC; wait(3 seconds);"
bin/duck -- "ADC >> Delay(2 seconds) >> DAC; wait(8 seconds);"
```


## Using the editor

First install dependencies with npm.
```
cd editor
npm i
```

Then start the editor with `npm start`.
When it's running press CMD+B to run your script.
