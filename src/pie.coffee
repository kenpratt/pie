fs            = require "node-fs"
path          = require "path"
async         = require "async"
CoffeeScript  = require "coffee-script"
glob          = require "glob"
minimatch     = require "minimatch"
fsWatchTree   = require "fs-watch-tree"
nStore        = require "nstore"
_             = require "underscore"

_mappings = []
_mtimes = null
_watch = null

noop = () -> null

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

runMapping = (m, src, cb) ->
  m.run src, m.dest(src), (err) ->
    console.log(err) if err
    return cb(err) if err
    updateMtime src, (err) ->
      console.log "finished", src
      cb(err)

startWatcher = () ->
  console.log "starting watcher"
  _watch = fsWatchTree.watchTree ".", { exclude: [".git", ".pie.db", "node_modules"] }, (event) ->
    console.log "got event", event
    unless event.isDelete()
      mappings = _.filter(_mappings, (m) -> minimatch(event.name, m.src, {}))
      console.log "applicable mappings", mappings
      async.forEach mappings, ((m) -> runMapping(m, event.name, noop)), noop

stopWatcher = () ->
  _watch.end()

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
            runMapping(m, f, innerCb)
          else
            console.log "skipping", f
            innerCb(null)

      async.forEach files, processFile, cb

  async.forEachSeries _mappings, processMapping, (err) ->
    return console.log("[ERROR]", err) if err
    console.log "build complete"
    startWatcher()
