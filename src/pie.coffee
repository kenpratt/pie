fs           = require "node-fs"
path         = require "path"
async        = require "async"
CoffeeScript = require "coffee-script"
glob         = require "glob"
nStore       = require "nstore"
_            = require "underscore"

_mappings = []
_mtimes = null

load = (cb) ->
  evaluatePiefile (err) ->
    return cb(err) if err
    _mtimes = nStore.new(".pie.db", cb)

evaluatePiefile = (cb) ->
  fs.readFile "Piefile", (err, code) ->
    return cb("No Piefile found. Please create one :)") if err && err.code == "ENOENT"
    return cb(err) if err
    res = CoffeeScript.compile(code.toString(), {})
    eval(res)
    cb(null)

map = (src, dest, run) ->
  _mappings.push { src: src, dest: dest, run: run }

getMtime = (filename, cb) ->
  fs.stat filename, (err, stats) ->
    return cb(err) if err
    cb(null, stats.mtime.getTime())

updateMtime = (filename, cb) ->
  getMtime filename, (err, mtime) ->
    return cb(err) if err
    _mtimes.save(filename, mtime, cb)

hasChanged = (filename, cb) ->
  _mtimes.get filename.toString(), (err, prev) ->
    if !err && prev
      getMtime filename, (err, mtime) ->
        return cb(err) if err
        cb(null, mtime != prev)
    else
      cb(null, true)

load (err) ->
  return console.log("[ERROR]", err) if err
  processMapping = (m, cb) ->
    console.log "running mapping", m
    glob m.src, {}, (err, files) ->
      return cb(err) if err

      console.log "found files", m.src, files
      processFile = (f, innerCb) ->
        hasChanged f, (err, changed) ->
          return innerCb(err) if err
          if changed
            m.run f, m.dest(f), (err) ->
              return innerCb(err) if err
              updateMtime f, (err) ->
                console.log "finished", f
                innerCb(err)
          else
            console.log "skipping", f
            innerCb(null)

      async.forEach files, processFile, cb

  async.forEachSeries _mappings, processMapping, (err) ->
    return console.log("[ERROR]", err) if err
    console.log "build complete"
