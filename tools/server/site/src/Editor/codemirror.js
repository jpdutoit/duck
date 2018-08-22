import CodeMirror from 'codemirror';
import './code-completion';

function parseErrors(text) {
  const found = [];
  const errors = (text || '').split('\n');
  for (let i = 0; i < errors.length; ++i) {
    let m = errors[i].match(/^[.a-zA-Z0-9_\-/]*\((\d+):(\d+)-(?:(\d+):)?(\d+)\):\s+(.*)/);
    if (!m) {
      m = errors[i].match(/^[.a-zA-Z0-9_\-/]*\((\d+):(\d+)\):\s+(.*)/);
      if (m) {
        m[5] = m[3];
        m[3] = m[1];
        m[4] = m[2];
      }
    }
    if (m) {
      found.push({
        from: CodeMirror.Pos(+m[1] - 1, m[2] - 1),
        to: CodeMirror.Pos(+(m[3] || m[1]) - 1, m[4]),
        message: m[5],
      });
    }
  }
  return found;
}

function getAnnotations(validator, callback) {
  return (code, updateLinting, options, cm) => {
    validator(code, (output) => {
      const errors = parseErrors(output);
      cm.operation(() => {
        updateLinting(cm, errors);
      });
      if (callback) callback(errors);
    });
  };
}

function createDoc(text) {
  const doc = CodeMirror.Doc(text, 'text/x-d');
  return doc;
}

function initialize(node, options) {
  options.validateCode = options.validateCode || (() => {});
  options.executeCode = options.executeCode || (() => {});
  const editor = CodeMirror(node, {
    value: options.value,
    lineNumbers: true,
    mode: 'text/x-d',
    theme: 'monokai',
    gutter: true,
    gutters: ['CodeMirror-lint-markers'],
    autofocus: true,
    viewportMargin: Infinity,
    //singleLineStringErrors: false,
    //lineNumberFormatter: a => '',
    lint: {
      getAnnotations: getAnnotations(options.validateCode),
      async: true,
      delay: 125,
    },
  });

  // Show hints on edit
  editor.on('change', (editor, change) => {
    const cursor = editor.doc.getCursor();
    const line = editor.doc.getLine(cursor.line);

    editor.showHint({
      hint: CodeMirror.hint.duck,
      completeSingle: false,
      closeOnUnfocus: true,
      customKeys: {
        Up: 'Up',
        Down: 'Down',
        PageUp: 'PageUp',
        PageDown: 'PageDown',
        Home: 'Home',
        End: 'End',
        Enter: 'Enter',
        Esc: 'Esc',
        Left(cm, handle) { handle.close(); return cm.Pass; },
        Right(cm, handle) { handle.close(); return cm.Pass; },
      },
    });
  });

  // Add tab helper short-cuts
  editor.addKeyMap({
    Tab(cm) {
      let cursor = cm.getCursor();
      const line = cm.getLine(cursor.line);
      //console.log('tab', cursor.ch, line.length);

      if (cursor.ch >= line.length) {
        cm.replaceSelection('    ', 'end');
        return true;
      }

      cursor = { line: cursor.line, ch: cursor.ch };

      if (line[cursor.ch] !== ' ' && line[cursor.ch] !== '\t') {
        for (; cursor.ch < line.length && line[cursor.ch] !== ' ' && line[cursor.ch] !== '\t'; ++cursor.ch);
        for (; cursor.ch < line.length && line[cursor.ch] === ' ' || line[cursor.ch] === '\t'; ++cursor.ch) {}
      } else {
        for (; cursor.ch < line.length && line[cursor.ch] === ' ' || line[cursor.ch] === '\t'; ++cursor.ch) ;
        for (; cursor.ch < line.length && line[cursor.ch] !== ' ' && line[cursor.ch] !== '\t'; ++cursor.ch) ;
      }

      setTimeout(() => {
        editor.getDoc().setCursor(cursor);
      }, 0);
      //else cm.replaceSelection('   ' , 'end');
      return false;
    },
  });

  editor.addKeyMap({
    'Cmd-B': (cm) => {
      options.executeCode(cm.getDoc().getValue());
    },
    'Shift-Tab': (cm) => {
      let cursor = cm.getCursor();
      const line = cm.getLine(cursor.line);
      cursor = { line: cursor.line, ch: cursor.ch };
      if (line[cursor.ch - 1] !== ' ' && line[cursor.ch - 1] !== '\t') {
        for (; cursor.ch > 0 && line[cursor.ch - 1] !== ' ' && line[cursor.ch - 1] !== '\t'; --cursor.ch) { /* empty */ }
        for (; cursor.ch > 0 && line[cursor.ch] === ' ' || line[cursor.ch] === '\t'; --cursor.ch) {}
      } else {
        for (; cursor.ch > 0 && line[cursor.ch-1] === ' ' || line[cursor.ch-1] === '\t'; --cursor.ch) {}
        for (; cursor.ch > 0 && line[cursor.ch-1] !== ' ' && line[cursor.ch-1] !== '\t'; --cursor.ch) {}
      }
      setTimeout(() => {
        editor.getDoc().setCursor(cursor);
      }, 0);
      return false;
    },
  });

  // Add a class for the active line
  let currentHandle, currentLine;
  function updateLineInfo(cm) {
    const line = cm.getCursor().line, handle = cm.getLineHandle(line);
    if (handle === currentHandle && line === currentLine) return;
    if (currentHandle) {
      cm.removeLineClass(currentHandle, 'background', 'cm-active-line');
      //cm.clearMarker(currentHandle);
    }
    currentHandle = handle; currentLine = line;
    //cm.setLineClass(currentHandle, null, 'cm-active-line');
    cm.addLineClass(currentHandle, 'background', 'cm-active-line');
    //cm.setMarker(currentHandle, String(line + 1));
  }
  editor.on('cursorActivity', () => {
    updateLineInfo(editor);
  });
  return editor;
}

export default {
  initialize,
};
