import "babel-polyfill";
import * as Inferno from 'inferno';
import { linkEvent, Component } from 'inferno';
import 'codemirror/mode/d/d.js';
import 'codemirror/lib/codemirror.css';
import 'codemirror/addon/hint/show-hint.css'
import 'codemirror/addon/lint/lint.css'
import 'codemirror/theme/monokai.css'
import WaveSurfer from 'wavesurfer.js/src/wavesurfer'
import CodeMirror from './codemirror';
import './style.css';

function parseQueryString(query) {
  query = (query || "").slice(1);
  var settings = query.split("&");
  var object = {};
  for (var i = 0; i < settings.length; ++i) {
    var parts = settings[i].split("=");
    object[decodeURIComponent(parts[0])] = decodeURIComponent(parts[1]);
  }
  return object;
}

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
        let result = await response.json()
        return {
          hash: result.hash,
          errors: result.errors,
          audio: result.audio
        }
      })
  }
  static load(hash) {
    if (!hash) return Promise.resolve("");
    return fetch("/code?hash=" + hash, { method: "GET" })
      .then(async response => response.text())
      .catch(e => "");
  }
}

export default class Editor extends Component {
  constructor(props) {
    super(props);
    this.state = {
      containsErrors: true
    };
  }

  getCode() {
    return this.state.editor.getDoc().getValue();
  }

  play() {
    if (this.state.containsErrors || !this.state.playbackUrl) return;

    this.state.waveSurfer.empty();
    this.state.waveSurfer.load(this.state.playbackUrl);
    this.state.waveSurfer.play();
  }

  share() {
    if (this.state.containsErrors) return;
  }

  componentDidMount() {
    var query = parseQueryString(document.location.search);
    API.load(query.hash).then(code => {
        setTimeout(() => this.createEditor(code), 100);
      });
  }

  componentWillUnmount() {
  }

  validateCode(code) {
    return API.validate(code)
      .then(result => {
        this.setState(Object.assign(this.state,  {
          containsErrors: !!result.errors,
          playbackUrl: result.audio
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

    this.state.waveSurfer = new WaveSurfer({
      container: this.waveSurferElement,
      backend: 'MediaElement',
      normalize: true,
      //pixelRatio: 1,
      cursorColor: "#ffaa",
      cursorWidth: 3,
      interact: true,
      fillParent: true,
      scrollParent: true,
      progressColor: "#999",
      plugins: [
      ]
    });

    this.state.waveSurfer.init();
    if (this.state.document) {
      this.state.editor.swapDoc(this.state.document);
    } else {
      this.state.document = this.state.editor.getDoc();
    }
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
        <div id="footer-container" class="container">
          <audio id="player" controls >
            <source id="player-source" src="" type="audio/mpeg"/>
            Your browser does not support the audio element.
          </audio>
        </div>
        <div id="wavesurfer-outer-container" class="container">
          <div id="wavesurfer-container" ref={(node) => { this.waveSurferElement = node; }} ></div>
        </div>
      </div>
    );
  }
}
