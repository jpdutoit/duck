import "babel-polyfill";
import * as Inferno from 'inferno';
import { Component } from 'inferno';
import 'codemirror/mode/d/d.js';
import 'codemirror/lib/codemirror.css';
import 'codemirror/addon/hint/show-hint.css'
import 'codemirror/addon/lint/lint.css'
import 'codemirror/theme/monokai.css'
import CodeMirror from './codemirror';
import './style.css';

function Window({ className, children }) {
  return (
    <div id="Window" className={`Window ${className}`}>
      { children }
    </div>
  );
}

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

export default class Editor extends Component {
  constructor(props) {
    super(props);
    this.state = {
      containsErrors: true,
      hash: window.app.dataset.hash,
      imageHash: window.app.dataset.hash
    };
  }

  getCode() {
    return this.state.editor.getDoc().getValue();
  }

  play() {
    if (this.state.containsErrors || !this.state.hash) return;

    if (this.audioElement) {
      this.audioElement.pause();
      this.audioElement = null;
    }
    this.audioElement = new Audio("/audio?hash=" + this.state.hash);
    this.audioElement.play();

    this.setState(Object.assign(this.state,  {
      imageHash: this.state.hash
    }));
  }

  share() {
    if (this.state.containsErrors) return;
  }

  componentDidMount() {
    this.createEditor(unescape(window.app.dataset.code));
  }

  componentWillUnmount() {
  }

  validateCode(code) {
    return API.validate(code)
      .then(result => {
        this.setState(Object.assign(this.state,  {
          containsErrors: !!result.errors,
          hash: result.hash
        }))
        this.context.router.history.replace("/edit?hash=" + result.hash)
        return result.errors
      })
      .catch(e => {
        this.setState(Object.assign(this.state, { containsErrors: true }))
        console.log(e)
        return ""
      });
  }

  createEditor(initialCode) {
    this.state.editor = CodeMirror.initialize(this.node, {
      value: initialCode || "",
      validateCode: (code, callback) => {
        this.validateCode(code).then(callback)
      },
      executeCode: (code) => this.play()
    });

    if (this.state.document) {
      this.state.editor.swapDoc(this.state.document);
    } else {
      this.state.document = this.state.editor.getDoc();
    }
  }

  handleImageError() {
    this.setState(Object.assign(this.state, {
      imageHash: undefined
    }))
  }

  render() {
    return (
      <div className={'Editor ' + (this.state.containsErrors ? 'contains-errors' : '')}>
        <div id="header-container" class="container">
          <div class="button-bar">
            {/*<button id="share-button" class="bar-button" onClick={this.share.bind(this)}>💾</button>*/}
            <button id="play-button" class="bar-button" onClick={this.play.bind(this)}>▶</button>
          </div>
        </div>
        <div className="codemirror-container container" ref={(node) => { this.node = node; }} />
        <div id="waveform-container" class="container">
          <img id="waveform"
               class={this.state.containsErrors || !this.state.imageHash ? "hidden" : ""}
               src={this.state.containsErrors && this.state.imageHash ? "" : "/image?hash=" + this.state.imageHash}
               onError={() => this.handleImageError()}/>
        </div>
      </div>
    );
  }
}
