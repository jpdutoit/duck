import * as CodeMirror from 'codemirror';

import 'codemirror/addon/hint/show-hint';
import 'codemirror/addon/lint/lint';
import 'codemirror/mode/d/d';

const symbols = {
  SinOsc: 'SinOsc',
  Clock: 'Clock',
  Square: 'Square',
  Triangle: 'Triangle',
  SawTooth: 'SawTooth',
  Pat: 'Pat',
  Pitch: 'Pitch',
  AR: 'AR',
  ScaleQuant: 'ScaleQuant',
  ADSR: 'ADSR',
  Delay: 'Delay',
  Echo: 'Echo',
  ADC: 'ADC',
  DAC: 'DAC',
  Osc: ['SinOsc', 'Square', 'Triangle', 'SawTooth'],
  UGen: ['Clock', 'SinOsc'],
  WhiteNoise: 'WhiteNoise',
};

const desc = {
  SinOsc: 'Sine oscillator',
  Triangle: 'Triangle oscillator',
  SawTooth: 'Saw-tooth oscillator',
  Square: 'Square wave oscillator',
  Clock: 'Clock generator',
  Pitch: 'Convert piano note number to frequency (49 => A440)',
  AR: 'Attack-release envelope',
  ADSR: 'Attack-sustain-decay-release envelope',
  Delay: 'Time delay',
  Echo: 'Echos samples with a delay',
  ADC: 'Audio input (Analog -> Digital)',
  DAC: 'Audio output (Digital -> Analog)',
  Pat: 'Pattern generator',
  WhiteNoise: 'White noise generator',
};

const help = {
  SinOsc: 'SinOsc',
};

const re = new RegExp(/[a-zA-Z][a-zA-Z0-9]*$/);
const typedef = new RegExp(/[a-z][a-zA-Z0-9_]*\s*:\s*([A-Z]?[a-zA-Z0-9_]*)$/);
const ctor = new RegExp(/([A-Z][a-zA-Z]+)(\s+[a-zA-Z]+)?\s*\([^)]*$/);

function getHint(identifier) {
  const description = desc[identifier];
  if (description) {
    return {
      text: identifier,
      displayText: `${identifier} - ${description}`,
    };
  }
  return {
    text: identifier,
    displayText: identifier,
  };
}

function findCompletions(text) {
  if (text === null || text === undefined) { return []; }

  const completions = [];
  Object.keys(symbols).forEach((key) => {
    const keys = symbols[key];
    if (key !== text && key.indexOf(text) === 0) {
      if (typeof keys === 'string') {
        completions.push(getHint(keys));
      } else {
        for (let i = 0; i < keys.length; ++i) {
          completions.push(getHint(keys[i]));
        }
      }
    }
  });
  return completions;
}


function showHint(editor) {
  const cursor = editor.getCursor();

  const line = editor.getLine(cursor.line).slice(0, cursor.ch);
  let match;
  if ((match = line.match(typedef))) {
    return {
      list: findCompletions(match[1]),
      from: CodeMirror.Pos(cursor.line, cursor.ch - match[1].length),
      to: cursor,
    };
  }

  /*if ((match = line.match(ctor))) {
    return {
      list: [{
        hint() {},
        displayText: help[match[1]],
      }],
      from: cursor,
      to: cursor,
    };
  }*/

  if (line[cursor.ch - 1] === ' ' && line[cursor.ch - 1] === '\t') {
    return {};
  }

  match = line.match(re);
  const str = match && match[0];
  let start;
  if (str && str.length > 0) {
    start = cursor.ch - str.length;
  } else {
    start = cursor.ch;
  }

  return {
    list: findCompletions(str),
    from: CodeMirror.Pos(cursor.line, start),
    to: cursor,
  };
}

CodeMirror.registerHelper('hint', 'duck', showHint);


export default {
  showHint
};
