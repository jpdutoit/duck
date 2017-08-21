import Inferno, { linkEvent } from 'inferno';
import Component from 'inferno-component';
import 'codemirror/mode/d/d.js';
import 'codemirror/lib/codemirror.css';
import 'codemirror/addon/hint/show-hint.css'
import 'codemirror/addon/lint/lint.css'
import 'codemirror/theme/monokai.css'
import WaveSurfer from 'wavesurfer.js/src/wavesurfer'

//import MinimapPlugin from 'wavesurfer.js/dist/plugin/wavesurfer.minimap.min.js';

//import * as WaveSurfer from 'wavesurfer/dist/wavesurfer'
//import 'wavesurfer/plugin/wavesurfer.spectrogram'

import CodeMirror from './codemirror';
import './style.css';
import request from 'browser-request';

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

export default class Editor extends Component {
  constructor(props) {
    super(props);
    this.state = {
    };
  }

  getCode() {
    return this.state.editor.getDoc().getValue();
  }

  validateCode(text, callback) {
    var encoded = encodeURIComponent(text);
    window.browserHistory.replace("/edit?code=" + encoded);

    request({
        method: "POST",
        url: "/check",
        body: text
      },
      (error, response, body) => {
        let containsErrors = response.statusCode >= 300
        this.setState(Object.assign(this.state,  {
          containsErrors
        }));
        callback(body);
      }
    )
  }

  executeCode(code) {
    if (this.state.containsErrors) return;

    //console.log("Play", code);
    var encoded = encodeURIComponent(code);
    let url = "/run?code=" + encoded;
    //document.getElementById('player-source').src = url;
    //document.getElementById('player').load();
    //document.getElementById('player').play();

    this.state.waveSurfer.empty();
    this.state.waveSurfer.load(url);
    this.state.waveSurfer.play();
  }

  play() {
    if (this.state.containsErrors) return;
    this.executeCode(this.getCode());
  }

  share() {
    if (this.state.containsErrors) return;
  }

  componentDidMount() {
    setTimeout(() => {
      var query = parseQueryString(document.location.search);
      console.log(this.node);
      this.state.editor = CodeMirror.initialize(this.node, {
        value: query.code || "",
        validateCode: (code, callback) => { this.validateCode(code, callback); },
        executeCode: (code) => {
          this.executeCode(code);
        }
      });

      this.state.waveSurfer = new WaveSurfer({
        container: this.waveSurferElement,
        backend: 'MediaElement',
        normalize: true,
        pixelRatio: 2,
        fillParent: true,
        plugins: [
        ]
      });

      this.state.waveSurfer.init();
      if (this.state.document) {
        this.state.editor.swapDoc(this.state.document);
      } else {
        this.state.document = this.state.editor.getDoc();
      }

      if (query.code) {
        this.play();

      //var player = document.getElementById('player');
      //player.addEventListener('canplaythrough', () => { player.play(); }, false);
      }
    }, 100);
  }

  componentWillUnmount() {
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
