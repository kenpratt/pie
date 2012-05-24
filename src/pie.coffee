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

map = (src, dest, args...) ->
  if args.length == 1
    _mappings.push { src: src, dest: dest, run: args[0], options: {} }
  else if args.length == 2
    _mappings.push { src: src, dest: dest, run: args[1], options: args[0] }

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

globSrc = (m, cb) ->
  if _.isString(m.src)
    glob(m.src, cb)
  else if _.isArray(m.src)
    async.concat(m.src, glob, cb)
  else
    cb("mapping src must be string or array of strings")

matchesSrc = (m, file) ->
  if _.isString(m.src)
    minimatch(file, m.src, {})
  else if _.isArray(m.src)
    _.any m.src, (s) -> minimatch(file, s, {})
  else
    throw "mapping src must be string or array of strings"

processDest = (m, src) ->
  if _.isFunction(m.dest)
    m.dest(src)
  else
    m.dest

runMapping = (m, files, cb) ->
  console.log "running mapping", m
  async.filter files, ((f, innerCb) -> hasChanged(f, (err, res) -> innerCb(!err && res))), (changedFiles) ->
    unchangedFiles = _.without(files, changedFiles)

    run = (src, innerCb) ->
      m.run src, processDest(m, src), (err) ->
        return innerCb(err) if err
        innerCb(null)

    if m.options.batch
      console.log "batching"
      if changedFiles.length > 0
        run changedFiles, (err) ->
          return cb(err) if err
          async.forEach changedFiles, updateMtime, (err) ->
            console.log "finished"
            cb(err)
      else
        console.log "skipping all"
        cb(null)
    else
      console.log "not batching"
      #_.each unchangedFiles, (f) -> console.log("skipping #{f}")
      if changedFiles.length > 0
        x = (f, innerCb) ->
          run f, (err) ->
            return innerCb(err) if err
            updateMtime(f, innerCb)
        async.forEach changedFiles, x, cb
      else
        cb(null)

startWatcher = () ->
  console.log "Starting watcher"
  _watch = fsWatchTree.watchTree ".", { exclude: [".git", ".pie.db", "node_modules", "log", "tmp"] }, (event) ->
    console.log "got event", event
    unless event.isDelete()
      mappings = _.filter(_mappings, (m) -> matchesSrc(m, event.name))
      console.log "applicable mappings", mappings
      async.forEach mappings, ((m) -> runMapping(m, [event.name], noop)), noop

stopWatcher = () ->
  _watch.end()

load (err) ->
  return console.log("[ERROR]", err) if err

  processMapping = (m, cb) ->
    globSrc m, (err, files) ->
      return cb(err) if err
      runMapping(m, files, cb)

  async.forEachSeries _mappings, processMapping, (err) ->
    return console.log("[ERROR]", err) if err
    console.log "Build complete"
    startWatcher()
