const http = require('http')
const URL = require('url')
const fs = require('fs')
const childProcess = require("child_process")

const SERVER_PORT = process.env.DUCK_SERVER_PORT || 80;
const DUCK_EXECUTABLE = "../../bin/duck";
const FFMPEG_EXECUTABLE = "ffmpeg";
const FFMPEG_ARGUMENTS = "-i - -acodec libmp3lame -ac 2 -y -v 0";

const MEMORY_CACHE_TIMEOUT = 10 * 60 * 1000;
const DISK_CACHE_TIMEOUT = 3 * 24 * 60 * 60 * 1000;
const PROCESSING_TIMEOUT = 4000

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
    spawn(DUCK_EXECUTABLE, ["-t", "check", "--", code], (code, stdout, stderr) => {
      if (code == 0) {
        resolve();
      } else {
        reject({ message: stderr.toString() || "Internal compiler error" });
      }
    })
  });
}

function generateMp3(filename, code) {
  var exeFilename = filename;
  var mp3Filename = filename + ".mp3";
  return new Promise((resolve, reject) => {
    spawn(DUCK_EXECUTABLE, ["-t", "exe", "-o", exeFilename, "-e", "null", "--", code], (code, stdout, stderr) => {
      if (code == 0) {
        fs.chmodSync(exeFilename, 0700);
        childProcess.exec(`${filename} --output au | ${FFMPEG_EXECUTABLE} ${FFMPEG_ARGUMENTS} ${mp3Filename}`, {
          encoding: "buffer",
          timeout: PROCESSING_TIMEOUT
        }, (error, stdout, stderr) => {
            fs.unlink(exeFilename);
            if (!error)
              resolve(mp3Filename);
            else
              reject({ message: error.killed ? "Timeout" : "Encoding failed"});
          });
      } else {
        reject({ message: stderr.toString() || "Internal compiler error" });
      }
    })
  });
}

class Cache {
  static id(code, format) {
    var shasum = require('crypto').createHash('sha1');
    shasum.update(code);
    return format + "_" + shasum.digest('hex');
  }

  static get(code, format) {
    let id = Cache.id(code, format)
    let cached = Cache.entries[id]
    if (!cached)
      Cache.entries[id] = cached = new CacheEntry(id, code, format)
    return cached
  }

  static remove(id) {
    delete Cache.entries[id]
  }
}
Cache.entries = {}


class CacheEntry {
  constructor(id, code, format) {
    this.id = id
    this.generateMp3(code)
    this.autoRemove()
  }

  baseFilename() {
    return "/tmp/duck_tmp_" + this.id
  }

  generateMp3(code) {
    console.log("Generating:", this.id, "\n  ", code)
    this._promise = generateMp3(this.baseFilename(), code).then(filename => {
      this.filename = filename;
      return filename;
    })
  }

  get promise() {
    if (!this._promise) {
      console.log("Reloading from disk:", this.id)
      this._promise = Promise.resolve(this.filename)
    } else {
      console.log("Reusing from cache:", this.id)
    }
    this.autoRemove()
    return this._promise
  }

  autoRemove() {
    // Reset timeout to clear from memory
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      console.log("Clearing from memory:", this.id)
      this._promise = null;

      // After clearing from memory, add timeout to remove from disk
      if (this.filename) {
        this.timeout = setTimeout(() => {
          console.log("Clearing from disk:", this.id)
          Cache.remove(this.id)
          fs.unlink(this.filename);
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

    case "/run":
      if (method != "GET" && method != "POST") break;
      var code = url.query.code || body || "";
      var cacheItem = Cache.get(code, "mp3")
      cacheItem.promise.then((filename) => {
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
      var code = url.query.code || body || "";
      checkSyntax(code).then(() => {
          response.writeHead(200, {
            'Content-Type': 'text/plain'
          })
          response.write("OK");
          response.end();
        })
        .catch((error) => {
          response.writeHead(400, {
            'Content-Type': 'text/plain'
          })
          response.write(error.message);
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
