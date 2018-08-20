const http = require('http')
const URL = require('url')
const fs = require('fs')
const childProcess = require("child_process")

const SERVER_PORT = process.env.DUCK_SERVER_PORT || 80;
const DUCK_EXECUTABLE = "../../bin/duck";
const CODE_STORAGE = "../../storage";
const FFMPEG_EXECUTABLE = "sox";
const FFMPEG_ARGUMENTS = "-t au -";

const MEMORY_CACHE_TIMEOUT = 10 * 60 * 1000;
const DISK_CACHE_TIMEOUT = 3 * 24 * 60 * 60 * 1000;
const PROCESSING_TIMEOUT = 4000;

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

function checkSyntax(code) {
  return new Promise((resolve, reject) => {
    spawn(DUCK_EXECUTABLE, ["-t", "check", code], (code, stdout, stderr) => {
      if (code == 0) {
        resolve();
      } else {
        reject({ message: stderr.toString().replace(/^[^(]*/mg, "") || "Internal compiler error" });
      }
    })
  });
}

function generateMp3(exeFilename, mp3Filename, code) {
  console.log("Generate mp3:", code, "=>", mp3Filename);
  return new Promise((resolve, reject) => {
    spawn(DUCK_EXECUTABLE, ["-t", "exe", "-o", exeFilename, "-e", "null", code], (code, stdout, stderr) => {
      if (code == 0) {
        fs.chmodSync(exeFilename, 0700);
        childProcess.exec(`${exeFilename} --output au | ${FFMPEG_EXECUTABLE} ${FFMPEG_ARGUMENTS} ${mp3Filename}`, {
          encoding: "buffer",
          timeout: PROCESSING_TIMEOUT
        }, (error, stdout, stderr) => {
            fs.unlink(exeFilename, () => {});
            if (!error)
              resolve(mp3Filename);
            else {
              console.log(error);
              reject({ message: error.killed ? "Timeout" : "Encoding failed"});
            }
          });
      } else {
        reject({ message: stderr.toString() || "Internal compiler error" });
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
    return cached
  }

  static getByHash(id) {
    if (!id.match(/^[0-9a-f]+$/)) return undefined;

    let cached = Cache.entries[id]
    if (!cached) {
      Cache.entries[id] = cached = new CacheEntry(id)
    }
    return cached
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
          reject({ message: "Not found"})
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
            reject({ message: "Could not write file" });
          }
        })
      })
    this._codePromise.catch(e => console.log("Error saving code: ", e));
  }

  generateMp3() {
    this._mp3Promise =
      (this._codePromise || this.loadCode())
      .then(codeFilename => {
        return generateMp3(this.tmp, this.tmp + ".mp3", codeFilename)
          .catch(e => {
            console.log("Error generating mp3: ", e)
            throw e;
          });
        })
      .then(filename => {
        this.mp3Filename = filename
        return filename
      })
    this._codePromise.catch(e => {
      this._mp3Promise = undefined;
    });
  }

  get mp3() {
    if (!this._mp3Promise) {
      if (this.mp3Filename) {
        console.log("Reloading from disk:", this.id)
        this._mp3Promise = Promise.resolve(this.mp3Filename)
      } else {
        this.generateMp3();
      }
    } else {
      console.log("Reusing from cache:", this.id)
    }
    this.autoRemove()
    return this._mp3Promise
  }

  checkSyntax() {
    this._checkPromise =
      (this._codePromise || this.loadCode())
      .then(codeFilename => checkSyntax(codeFilename))
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
      this._mp3Promise = null;
      this._checkPromise = null;

      // After clearing from memory, add timeout to remove from disk
      if (this.mp3Filename) {
        this.timeout = setTimeout(() => {
          console.log("Clearing from disk:", this.id)
          Cache.remove(this.id)
          fs.unlink(this.mp3Filename);
          this.mp3Filename = null;
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
    switch(url.pathname) {

    case "/edit":
      if (method != "GET") break;
      response.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8'
      })
      var stream = fs.createReadStream("built/index.html");
      stream.pipe(response);
      return;

    case "/bundle.js":
      if (method != "GET") break;
      response.writeHead(200, {
        'Content-Type': 'application/javascript'
      })
      var stream = fs.createReadStream("built/bundle.js");
      stream.pipe(response);
      return;

    case "/code":
      if (method != "GET" && method != "POST") break;
      var cacheItem = Cache.getByHash(url.query.hash);
      if (cacheItem)
      cacheItem.code.then((filename) => {
          response.writeHead(200, {
            'Content-Type': 'text/duck'
          })
          var stream = fs.createReadStream(filename);
          stream.pipe(response);
        })
        .catch((error) => {
          response.writeHead(400, {
            'Content-Type': 'text/plain'
          })
          response.write(error.message);
          response.end();
        });
    return;
    case "/run":
      if (method != "GET" && method != "POST") break;
      var cacheItem = Cache.getByHash(url.query.hash);
      if (cacheItem)
      cacheItem.mp3.then((filename) => {
          response.writeHead(200, {
            'Content-Type': 'audio/mpeg'
          })
          var stream = fs.createReadStream(filename);
          stream.pipe(response);
        })
        .catch((error) => {
          response.writeHead(400, {
            'Content-Type': 'text/plain'
          })
          response.write(error.message);
          response.end();
        });
      return;

    case "/check":
      if (method != "GET" && method != "POST") break;
      var code = url.query.code || body;
      var cacheItem = Cache.getWithCode(code);
      if (cacheItem)
      cacheItem.check.then(() => {
          response.writeHead(200, {
            'Content-Type': 'text/plain'
          })
          response.write(JSON.stringify({ "hash": cacheItem.id, "mp3": `/run?hash=${cacheItem.id}` }));
          response.end();
        })
        .catch((error) => {
          response.writeHead(400, {
            'Content-Type': 'text/plain'
          })
          response.write(JSON.stringify({ "hash": cacheItem.id, "message": error.message }));
          response.end();
        });
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
