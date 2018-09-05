const http = require('http')
const URL = require('url')
const fs = require('fs')
const childProcess = require("child_process")

const ETAG = '"' + Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15) + '"';
const AUDIO_FORMAT = "flac"
const AUDIO_FORMAT_MIME = "audio/flac"
const SERVER_PORT = process.env.DUCK_SERVER_PORT || 80;
const DUCK_EXECUTABLE = "../../bin/duck";
const CODE_STORAGE = "../../storage";
const FFMPEG_EXECUTABLE = "sox";
const FFMPEG_ARGUMENTS = "-t au -";

const MEMORY_CACHE_TIMEOUT = 10 * 60 * 1000;
const DISK_CACHE_TIMEOUT = 3 * 24 * 60 * 60 * 1000;
const PROCESSING_TIMEOUT = 4000;

function serverError(status, message) {
  let error = new Error()
  error.status = status
  error.message = message || "Internal server error"
  return error
}

fs.mkdir(CODE_STORAGE, (error) => {
  if (error && error.code != "EEXIST")
    console.log("Error creating folder" + CODE_STORAGE, error)
  });

function spawn(cmd, args, callback) {
  const child = childProcess.spawn(cmd, args || []);

  let stdout = '', stderr = '';
  child.stdout.on('data', (buffer) => { stdout += buffer.toString(); });
  child.stderr.on('data', (buffer) => { stderr += buffer.toString(); });
  child.on('exit', (code) => {
    callback(code, stdout, stderr);
  });

  return child;
}

function checkSyntax(hash, code) {
  return new Promise((resolve, reject) => {
    spawn(DUCK_EXECUTABLE, ["-t", "check", code], (code, stdout, stderr) => {
      let errors
      if (code != 0) {
        errors = stderr.toString().replace(/^[^(]*/mg, "")
        if (!errors) {
          console.error("Internal compiler error:", hash);
          errors = "Internal compiler error";
        }
      }
      resolve({
        "hash": hash,
        "errors": errors
      });
    })
  });
}

function generateAudio(exeFilename, audioFilename, code) {
  console.log("Generate audio:", code, "=>", audioFilename);
  return new Promise((resolve, reject) => {
    spawn(DUCK_EXECUTABLE, ["-t", "exe", "-o", exeFilename, "-e", "null", code], (code, stdout, stderr) => {
      if (code == 0) {
        fs.chmodSync(exeFilename, 0700);
        childProcess.exec(`${exeFilename} --output au | ${FFMPEG_EXECUTABLE} ${FFMPEG_ARGUMENTS} ${audioFilename} remix 1,2`, {
          encoding: "buffer",
          timeout: PROCESSING_TIMEOUT
        }, (error, stdout, stderr) => {
            fs.unlink(exeFilename, () => {});
            if (!error)
              resolve(audioFilename);
            else {
              console.log(error);
              reject(serverError(500, error.killed ? "Timeout" : "Encoding failed"));
            }
          });
      } else {
        reject(serverError(500, stderr.toString()));
      }
    })
  });
}

class Cache {
  static id(code) {
    var shasum = require('crypto').createHash('sha1');
    shasum.update(code);
    return shasum.digest('hex');
  }

  static getWithCode(code) {
    let id = Cache.id(code)
    let cached = Cache.entries[id]
    if (!cached) {
      Cache.entries[id] = cached = new CacheEntry(id, code)
      cached.saveCode(code)
    }
    return Promise.resolve(cached)
  }

  static getByHash(id) {
    if (!id || !id.match(/^[0-9a-f]+$/)) return Promise.reject(serverError(404, "Not found"))

    let cached = Cache.entries[id]
    if (!cached) {
      Cache.entries[id] = cached = new CacheEntry(id)
    }
    return Promise.resolve(cached)
  }

  static remove(id) {
    delete Cache.entries[id]
  }
}
Cache.entries = {}


class CacheEntry {
  constructor(id, code) {
    this.id = id
    this.autoRemove()
  }

  get tmp() {
    return "/tmp/duck_tmp_" + this.id
  }

  get codeFilename() {
    return `${CODE_STORAGE}/${this.id}.duck`
  }

  loadCode() {
    console.log("Load duck:", this.codeFilename);
    this._codePromise = new Promise((resolve, reject) => {
      fs.exists(this.codeFilename, (exists) => {
        if (exists)
          resolve(this.codeFilename)
        else
          reject(serverError(404, "Not found"))
      })
    });
    this._codePromise.catch(e => {
      console.log("Error loading code: ", e);
      this._codePromise = undefined;
    });
    return this._codePromise
  }

  saveCode(code) {
    console.log("Write duck:", this.codeFilename);
    this._codePromise = new Promise((resolve, reject) => {
        fs.writeFile(this.codeFilename, code, (error) => {
          if (!error)
            resolve(this.codeFilename);
          else {
            reject(serverError(500, "Could not write file"));
          }
        })
      })
    this._codePromise.catch(e => console.log("Error saving code: ", e));
  }

  generateAudio() {
    this._audioPromise =
      (this._codePromise || this.loadCode())
      .then(codeFilename => {
        return generateAudio(this.tmp, this.tmp + "." + AUDIO_FORMAT, codeFilename)
          .catch(e => {
            console.log("Error generating audio: ", e)
            throw e;
          });
        })
      .then(filename => {
        this.audioFilename = filename
        return filename
      })
    this._audioPromise.catch(e => {
      this._audioPromise = undefined;
    });
  }

  get audio() {
    if (!this._audioPromise) {
      if (this.audioFilename) {
        console.log("Reloading audio from disk:", this.id)
        this._audioPromise = Promise.resolve(this.audioFilename)
      } else {
        this.generateAudio();
      }
    } else {
      console.log("Reusing from cache:", this.id)
    }
    this.autoRemove()
    return this._audioPromise
  }

  generateImage() {
    let imageFilename = this.tmp + ".png"
    console.log("Generate image:", this.id, "=>", imageFilename);
    return this.audio
      .then(audio => new Promise((resolve, reject) => {
        childProcess.exec(`audiowaveform -i ${audio} -o ${imageFilename} --no-axis-labels -z auto -w 1600 -h 256 --waveform-color cccccc --background-color 272822`, {
          encoding: "buffer",
          timeout: PROCESSING_TIMEOUT
        }, (error, stdout, stderr) => {
            if (!error) {
              this.imageFilename = imageFilename;
              resolve(imageFilename);
            }
            else {
              reject(serverError(500, error.killed ? "Timeout" : "Image generation failed"));
            }
          });
        })
      )
  }

  get image() {
    if (!this._imagePromise) {
      if (this.imageFilename) {
        console.log("Reloading image from disk:", this.id)
        this._imagePromise = Promise.resolve(this.imageFilename)
      } else {
        this._imagePromise = this.generateImage();
      }
    } else {
      console.log("Reusing from cache:", this.id)
    }
    this.autoRemove()
    return this._imagePromise
  }

  checkSyntax() {
    this._checkPromise =
      (this._codePromise || this.loadCode())
      .then(codeFilename => checkSyntax(this.id, codeFilename))
    this._checkPromise.catch(e => "");
  }

  get check() {
    if (!this._checkPromise) {
      this.checkSyntax();
    } else {
      console.log("Checking from cache:", this.id)
    }
    this.autoRemove()
    return this._checkPromise
  }

  get code() {
    return (this._codePromise || this.loadCode())
  }

  autoRemove() {
    // Reset timeout to clear from memory
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      console.log("Clearing from memory:", this.id)
      this._audioPromise = null;
      this._checkPromise = null;
      this._imagePromise = null;

      // After clearing from memory, add timeout to remove from disk
      if (this.audioFilename) {
        this.timeout = setTimeout(() => {
          console.log("Clearing from disk:", this.id)
          Cache.remove(this.id)
          fs.unlink(this.audioFilename);
          this.audioFilename = null;
          fs.unlink(this.imageFilename);
          this.imageFilename = null;
        }, DISK_CACHE_TIMEOUT)
      } else {
        Cache.remove(this.id)
      }
    }, MEMORY_CACHE_TIMEOUT);
  }
}

const requestHandler = (request, response) => {
  const { headers, method } = request;
  const url = URL.parse(request.url, true);

  let body = [];
  request
  .on('error', (err) => { console.error(err); })
  .on('data', (chunk) => { body.push(chunk);})
  .on('end', () => {
    body = Buffer.concat(body).toString();

    // Poor man's etag
    if (request.headers["if-none-match"] == ETAG) {
      response.writeHead(304)
      response.end()
      return
    }

    function sendError(error) {
      response.writeHead(error.status || 500, {
        'Content-Type': 'text/plain'
      })
      response.write(error.message);
      response.end();
    }

    switch(url.pathname) {

    case "/edit":
      if (method != "GET") break;
      let hash = url.query.hash || ""
      Cache
        .getByHash(hash)
        .then(item => item.code)
        .then(filename => new Promise((resolve, reject) => {
          fs.readFile(filename, "utf8", (err, data) => resolve(data || ""))
        }))
        .catch(error => "")
        .then(code => {
          response.writeHead(200, {
            'Content-Type': 'text/html; charset=utf-8',
            ...(hash && {'ETag': ETAG})
          })
          response.write(`<html>
          <head>
            <title>Duck - ${hash}</title>
            <meta property="og:title" content="Duck"/>
            <meta property="og:description" content="${hash}"/>
            <meta property="og:type" content="music.song"/>
            ${ process.env.DUCK_OG_BASE ? `<meta property="og:url" content="${process.env.DUCK_OG_BASE}/edit?hash=${hash}"/>` : ""}
            ${ process.env.DUCK_OG_BASE ? `<meta property="og:image" content="${process.env.DUCK_OG_BASE}/image?hash=${hash}"/>` : ""}
            ${ process.env.DUCK_OG_BASE ? `<meta property="og:audio" content="${process.env.DUCK_OG_BASE}/audio?hash=${hash}"/>` : ""}
          </head>
          <body>
            <div id="app" data-hash="${hash}" data-code="${escape(code)}" ></div>
            <script src="bundle.js"></script>
          </body>
          </html>`)
          response.end();
        })
        .catch(e => logError)
      return;

    case "/bundle.js":
      if (method != "GET") break;
      response.writeHead(200, {
        'Content-Type': 'application/javascript',
        'ETag': ETAG
      })
      fs.createReadStream("built/bundle.js").pipe(response);
      return;

    case "/code":
      if (method != "GET") break;
      Cache
        .getByHash(url.query.hash)
        .then(item => item.code)
        .then((filename) => {
            response.writeHead(200, {
              'Content-Type': 'text/duck',
              'ETag': ETAG
            })
            var stream = fs.createReadStream(filename);
            stream.pipe(response);
          })
        .catch(e => sendError(e))
      return;

    case "/audio":
      if (method != "GET") break;
      Cache
        .getByHash(url.query.hash)
        .then(item => item.audio)
        .then((filename) => {
            response.writeHead(200, {
              'Content-Type': AUDIO_FORMAT_MIME,
              'ETag': ETAG
            })
            var stream = fs.createReadStream(filename);
            stream.pipe(response);
          })
        .catch(e => sendError(e))
      return;

    case "/image":
      if (method != "GET") break;
      Cache
        .getByHash(url.query.hash)
        .then(item => item.image)
        .then((filename) => {
            var stream = fs.createReadStream(filename);
            response.writeHead(200, {
              'Content-Type': "image/png",
              'ETag': ETAG
            })
            stream.pipe(response);
          })
        .catch(e => sendError(e))
      return;

    case "/check":
      if (method != "POST") break;
      Cache
        .getWithCode(url.query.code || body)
        .then(item => item.check)
        .then((result) => {
            response.writeHead(200, {
              'Content-Type': 'text/plain'
            })
            response.write(JSON.stringify(result));
            response.end();
          })
        .catch(e => sendError(e))
      return;

    default:
      break;
    }
    response.statusCode = 404;
    response.end();
  });
}

const server = http.createServer(requestHandler)

server.listen(SERVER_PORT, (err) => {
  if (err) {
    return console.log('something bad happened', err)
  }
  console.log(`Server is listening on ${SERVER_PORT}`)
})
