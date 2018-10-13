import 'codemirror/lib/codemirror.css';
import 'codemirror/addon/hint/show-hint.css'
import 'codemirror/addon/lint/lint.css'
import 'codemirror/theme/monokai.css'
import './style.css';

import CodeMirror from './codemirror';

class API {
  static validate(text) {
    var encoded = encodeURIComponent(text);
    return fetch("/check", {
        method: "POST",
        body: text
      })
      .then(async response => {
        if (!response.ok) throw new Error("Unexpected failure");
        return response.json()
      })
  }
}

export class DuckEditor {
  hash = undefined
  containsErrors = false
  imageHash = undefined

  constructor(options) {
    this.waveform = options.waveform
    this.editor = CodeMirror.initialize((editorElement) => {
      options.element.parentNode.replaceChild(editorElement, options.element);
      editorElement.classList.add("live")
      this.editorElement = editorElement
    }, {
      value: options.pre.innerText,
      validateCode: (code, callback) => {
        this.validateCode(code).then(callback)
      },
      executeCode: (code) => this.play()
    });

    if (this.waveform) {
      this.waveform.onerror = () => this.handleImageError()
    }

    this.update({
      containsErrors: true,
      hash: options.hash,
      imageHash: options.hash,
      onCreate: options.onCreate,
      onChangeHash: options.onChangeHash
    })

    this.onCreate && this.onCreate(this)
  }

  static create(options) {
    if (!options.element) return
    new DuckEditor(Object.assign({
      element: options.element,
      waveform: options.waveform,
      hash: options.element.dataset.hash || options.hash,
      pre: options.element.querySelector("pre") || options.element
    }, options))
  }

  static createAll(options) {
    let all = document.querySelectorAll(".CodeMirror[data-lang='duck']")
    all.forEach(element => {
      DuckEditor.create(Object.assign({element}, options))
    })
  }

  play() {
    if (this.containsErrors || !this.hash) return;

    if (this.audioElement) {
      this.audioElement.pause();
      this.audioElement = null;
    }
    this.audioElement = new Audio("/audio?hash=" + this.hash);
    this.audioElement.play();

    this.update({
      imageHash: this.hash
    })
  }

  get value() {
    return this.editor.getDoc().getValue();
  }

  validateCode(code) {
    return API.validate(code)
      .then(result => {
        this.update({
          hash: result.hash,
          containsErrors: !!result.errors
        })
        return result.errors
      })
      .catch(e => {
        this.update({
          containsErrors: true
        })
        return ""
      });
  }

  update(values) {
    const keys = Object.keys(values)
    const changed = {}
    keys.forEach(key => changed[key] = this[key] !== values[key])
    if (!keys.some(key => changed[key])) { return }
    Object.assign(this, values)

    if (this.waveform) {
      if ("imageHash" in changed)
        this.waveform.classList.toggle("hidden", !this.imageHash)
      if ("imageHash" in changed)
        this.waveform.src = "/image?hash=" + this.imageHash
    }

    if ("containsErrors" in changed)
      this.editorElement.classList.toggle('contains-errors', this.containsErrors)

    if ("hash" in changed) {
      this.onChangeHash && this.onChangeHash(this.hash, this)
    }
  }

  handleImageError() {
    this.update({
      imageHash: undefined
    })
  }
}

window.DuckEditor = DuckEditor;
