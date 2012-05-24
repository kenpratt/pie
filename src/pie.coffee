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
_db = null
_watch = null

noop = () -> null

load = (cb) ->
  evaluatePiefile (err) ->
    return cb(err) if err
    _db = nStore.new(".pie.db", cb)

evaluatePiefile = (cb) ->
  fs.readFile "Piefile", (err, code) ->
    return cb("No Piefile found. Please create one :)") if err && err.code == "ENOENT"
    return cb(err) if err
    res = CoffeeScript.compile(code.toString(), {})
    eval(res)
    cb(null)

map = (args...) ->
  _mappings.push(new Mapping(args...))

getMtime = (file, cb) ->
  fs.stat file, (err, stats) ->
    return cb(err) if err
    cb(null, stats.mtime.getTime())

printErr = (err) ->
  if err
    if err.stack?
      console.log(err.stack)
    else
      console.log(err.toString())

runAllMappings = (cb = noop) ->
  async.forEachSeries _mappings, ((m, innerCb) -> m.run(innerCb)), (err) ->
    return printErr(err) if err
    console.log "Build complete"

startWatcher = (cb = noop) ->
  console.log "Starting watcher"
  _watch = fsWatchTree.watchTree ".", { exclude: [".git", ".pie.db", "node_modules", "log", "tmp"] }, (event) ->
    console.log "Got event", event
    unless event.isDelete()
      mappings = _.filter(_mappings, (m) -> m.matchesSrc(event.name))
      console.log "Applicable mappings", _.map(mappings, (m) -> m.name)
      async.forEach mappings, ((m) -> m.runOnFiles([event.name], printErr)), printErr

stopWatcher = () ->
  _watch.end()


# represents a mapping / build target
# stores mtimes of source files so it can be smart later. mtimes are stored scoped
# to each mapping, so that the same source files can be used in multiple mappings.
class Mapping
  constructor: (@name, @src, @dest, args...) ->
    if args.length == 1
      @func = args[0]
      @options = {}
    else if args.length == 2
      @func = args[1]
      @options = args[0]

  updateMtime: (file, cb) ->
    getMtime file, (err, mtime) =>
      return cb(err) if err
      _db.save("#{@name}:#{file}", mtime, cb)

  hasChanged: (file, cb) ->
    _db.get "#{@name}:#{file}", (err, prev) ->
      if !err && prev
        getMtime file, (err, mtime) ->
          return cb(err) if err
          cb(mtime != prev)
      else
        cb(true)

  findSrcFiles: (cb) ->
    if _.isString(@src)
      glob(@src, cb)
    else if _.isArray(@src)
      async.concat(@src, glob, cb)
    else
      cb("mapping src must be string or array of strings")

  matchesSrc: (file) ->
    if _.isString(@src)
      minimatch(file, @src, {})
    else if _.isArray(@src)
      _.any @src, (s) -> minimatch(file, s, {})
    else
      throw "mapping src must be string or array of strings"

  run: (cb) ->
    @findSrcFiles (err, files) =>
      return cb(err) if err
      @runOnFiles(files, cb)

  runOnFiles: (files, cb) ->
    console.log "Running", @name, "on", files.length, "files"
    async.filter files, _.bind(@hasChanged, @), (changedFiles) =>
      unchangedFiles = _.without(files, changedFiles)

      if @options.batch
        if changedFiles.length > 0
          @execFunc changedFiles, (err) =>
            return cb(err) if err
            async.forEach changedFiles, _.bind(@updateMtime, @), cb
        else
          cb(null)
      else
        if changedFiles.length > 0
          x = (f, innerCb) =>
            @execFunc f, (err) =>
              return innerCb(err) if err
              @updateMtime(f, innerCb)
          async.forEach changedFiles, x, cb
        else
          cb(null)

  execFunc: (src, cb) ->
    try
      dest = if _.isFunction(@dest) then @dest(src) else @dest
      @func(src, dest, cb)
    catch err
      cb(err)


# do stuff on run
load (err) ->
  return printErr(err) if err
  runAllMappings(printErr)
