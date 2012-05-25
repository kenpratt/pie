fs            = require "node-fs"
path          = require "path"
async         = require "async"
CoffeeScript  = require "coffee-script"
glob          = require "glob"
minimatch     = require "minimatch"
fsWatchTree   = require "fs-watch-tree"
nStore        = require "nstore"
growl         = require "growl"
_             = require "underscore"


_tasks = {}
_mappings = []
_db = null
_watch = null


exports.run = () ->
  load (err) ->
    return printErr(err) if err
    target = process.argv[2] || "build"
    invoke target, (err) ->
      if err
       growl("Piefile\n#{shortErr(err)}")
       printErr(err)

noop = () -> null

load = (cb) ->
  # define a few default tasks
  task "build", "Build everything! (run all mappings, in the order defined)", (cb) ->
    runAllMappings(cb)

  task "watch", "Run a build and then start watching the filesystem for changes and triggering mappings as necessary", (cb) ->
    invoke "build", (err) ->
      return cb(err) if err
      startWatcher(cb)

  # slurp up the Piefile (can override the default tasks if it wants)
  evaluatePiefile (err) ->
    return cb(err) if err
    _db = nStore.new(".pie.db", cb)

evaluatePiefile = (cb) ->
  fs.readFile "Piefile", (err, code) ->
    return cb("No Piefile found. Please create one :)") if err && err.code == "ENOENT"
    return cb(err) if err
    try
      CoffeeScript.run(code.toString(), { filename: "Piefile" })
      cb(null)
    catch err
      growl("Piefile\n#{shortErr(err)}")
      printErr(err)

task = (name, args...) ->
  _tasks[name] = new Task(name, args...)

invoke = (name, cb) ->
  if _.isArray(name)
    async.forEachSeries(name, invoke, cb)
  else if t = _tasks[name]
    t.run(cb)
  else
    cb("No task named \"#{name}\" found")

map = (name, args...) ->
  m = new Mapping(name, args...)
  _mappings.push(m)
  task name, "Run #{name}", (cb) -> m.run(cb)

defineDefaultTasks = () ->

_.extend(global, { task: task, invoke: invoke, map: map })

getMtime = (file, cb) ->
  fs.stat file, (err, stats) ->
    return cb(err) if err
    cb(null, stats.mtime.getTime())

printErr = (err) ->
  if err
    if err.stack?
      console.log(err.stack)
    else
      console.log(shortErr(err))

shortErr = (err) ->
  if err.message?
    err.message
  else
    err.toString()

runAllMappings = (cb) ->
  async.forEachSeries _mappings, ((m, innerCb) -> m.run(innerCb)), (err) ->
    return cb(err) if err
    console.log "Build complete"
    growl "Build complete"
    cb(null)

startWatcher = (cb) ->
  console.log "Starting watcher"
  _watch = fsWatchTree.watchTree ".",
                                 { exclude: [".git", ".pie.db", "node_modules", "log", "tmp"] },
                                 watchEvent
  cb(null)

stopWatcher = () ->
  _watch.end()

watchEvent = (event) ->
  console.log "Got event", event
  unless event.isDelete()
    mappings = _.filter(_mappings, (m) -> m.matchesSrc(event.name))
    console.log "Applicable mappings", _.map(mappings, (m) -> m.name)
    async.forEach mappings, ((m) -> m.runOnFiles([event.name], printErr)), printErr


# just a lil' bit o' code
class Task
  constructor: (@name, @dest, @func) ->

  run: (cb) ->
    try
      @func(cb)
    catch err
      growl "#{@name}\n#{err}"
      cb(err)


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
            growl("#{@name}\n#{shortErr(err)}") if err
            return cb(err) if err
            async.forEach changedFiles, _.bind(@updateMtime, @), cb
        else
          cb(null)
      else
        if changedFiles.length > 0
          x = (f, innerCb) =>
            @execFunc f, (err) =>
              growl("#{f}\n#{shortErr(err)}") if err
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
