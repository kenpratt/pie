fs            = require "node-fs"
path          = require "path"
util          = require "util"
async         = require "async"
CoffeeScript  = require "coffee-script"
gaze          = require "gaze"
glob          = require "glob"
minimatch     = require "minimatch"
nStore        = require "nstore"
growl         = require "growl"
compilers     = require "./compilers"
optparse      = require "./optparse"
_             = require "underscore"

_cwd = process.cwd()
_switches = []
_tasks = {}
_mappings = []
_mappingsWatcher = null
_db = null
_runQueue = null

# the entry point (called from bin/pie)
exports.run = () ->
  load (err) ->
    return printErr(err) if err
    parser = new optparse.OptionParser(_switches)
    options = parser.parse(process.argv[2..])
    targets = options.arguments
    targets.push("list_tasks") if options.tasks
    targets.push("build") if targets.length == 0
    invoke targets, options, (err) ->
      if err
        growl("Piefile\n#{shortErr(err)}")
        printErr(err)

# bootstrap
load = (cb) ->
  option "-T", "--tasks", "List tasks"

  task "list_tasks", "Print out a list of tasks", (options, cb) ->
    _.each _.sortBy(_tasks, (t) -> t.name),
           (t) -> console.log _.sprintf("%-30s %s", "pie #{t.name}", t.desc)
    console.log ""
    _.each _.sortBy(_switches, (s) -> s[0]),
           (s) -> console.log _.sprintf("%-30s %s", "  #{s[0]}, #{s[1]}", s[2])
    console.log ""
    cb(null)

  # define a few default tasks
  task "build", "Build everything! (run all mappings, in the order defined)", runAllMappings

  task "clean", "Clean everything! (remove the files generated by the mappings)", cleanAllMappings

  task "watch", "Run a build, then start watching the filesystem for changes, triggering mappings as necessary", (options, cb) ->
    invoke "build", options, (err) ->
      return cb(err) if err
      watchMappings(options, cb)

  # slurp up the Piefile (can override the default tasks if it wants)
  evaluatePiefile (err) ->
    return cb(err) if err
    reloadDB(cb)

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

option = (args...) ->
  _switches.push(args)

task = (name, args...) ->
  _tasks[name] = new Task(name, args...)

invoke = (name, options, cb) ->
  if _.isArray(name)
    async.forEachSeries(name, ((name, innerCb) -> invoke(name, options, innerCb)), cb)
  else if t = _tasks[name]
    t.run(options, cb)
  else
    cb("No task named \"#{name}\" found")

map = (name, args...) ->
  m = new Mapping(name, args...)
  _mappings.push(m)
  task name, "Run #{name}", (options, cb) -> m.run(options, cb)

watch = (paths, eventHandler, cb = noop) ->
  w = new Watcher(paths, eventHandler)
  w.start (err) -> cb(err, w)

reloadDB = (cb) ->
  nStoreAlreadyFiredCallback = false
  _db = nStore.new ".pie.db", (err) ->
    if !nStoreAlreadyFiredCallback
      nStoreAlreadyFiredCallback = true
      cb(err)

# exports, available in global namespace of Piefile
_.extend(global, { option: option, task: task, invoke: invoke, map: map, compilers: compilers, watch: watch, reloadDB: reloadDB })

getMtime = (file, cb) ->
  fs.stat file, (err, stats) ->
    return cb(err) if err
    cb(null, stats.mtime.getTime())

printErr = (err) ->
  if err
    if err.stack?
      console.log red(err.stack)
    else
      console.log red(shortErr(err))

shortErr = (err) ->
  if err.message?
    err.message
  else
    err.toString()

runAllMappings = (options, cb) ->
  async.forEachSeries _mappings, ((m, innerCb) -> m.run(options, innerCb)), (err) ->
    return cb(err) if err
    console.log green("Build complete")
    growl "Build complete"
    cb(null)

rm = (f, innerCb) ->
  console.log "Deleting #{f}"
  try
    fs.unlink f, (err) ->
      console.log red("#{f}: #{err}") if err && err.code != "ENOENT"
      innerCb(null)
  catch err
    console.log red("#{f}: #{err}") if err && err.code != "ENOENT"
    innerCb(null)

cleanAllMappings = (options, cb) ->
  async.map _mappings, ((m, innerCb) -> m.clean(innerCb)), (err) ->
    return cb(err) if err
    rm ".pie.db", cb

watchMappings = (options, cb) ->
  _mappingsWatcher.stop() if _mappingsWatcher

  # calculate watch targets
  toWatch = _.uniq(_.flatten(_.map(_mappings, (m) -> m.src)))

  console.log "Starting watcher"
  _mappingsWatcher = watch(toWatch, handleMappingWatchEvent, cb)

handleMappingWatchEvent = (event, path) ->
  console.log "#{path} was #{event}"
  mappings = _.filter(_mappings, (m) -> m.matchesSrc(path))

  async.forEach mappings, (m, cb) ->
    unless event is "deleted" and !m.batch
      # run mapping on non-deletes, or if it's a deleted file in a batch mapping
      _runQueue.add(m, [path])
      cb()
    else
      # on a delete in non-batched mapping, delete the output file(s)
      m.cleanForFiles([path], cb)
  , printErr

noop = () -> null

red    = (str) -> "\x1B[0;31m#{str}\x1B[0m"
green  = (str) -> "\x1B[0;32m#{str}\x1B[0m"
yellow = (str) -> "\x1B[0;33m#{str}\x1B[0m"


# just a lil' bit o' code
class Task
  constructor: (@name, @desc, @func) ->

  run: (options, cb) ->
    try
      @func(options, cb)
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
    @batch = @options.batch

  updateMtime: (file, cb) =>
    getMtime file, (err, mtime) =>
      return cb(err) if err
      _db.save("#{@name}:#{file}", mtime, cb)

  clearMtime: (file, cb) =>
    _db.save("#{@name}:#{file}", null, cb)

  hasChanged: (file, cb) =>
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

  calculateDest: (f) =>
    if _.isFunction(@dest)
      @dest(f)
    else
      @dest

  outputFiles: (cb) ->
    @findSrcFiles (err, files) =>
      return cb(err) if err
      cb(null, _.uniq(_.flatten(_.map(files, @calculateDest))))

  matchesSrc: (file) ->
    if _.isString(@src)
      minimatch(file, @src, {})
    else if _.isArray(@src)
      _.any @src, (s) -> minimatch(file, s, {})
    else
      throw "mapping src must be string or array of strings"

  run: (options, cb) ->
    @findSrcFiles (err, files) =>
      return cb(err) if err
      @runOnFiles(files, options, cb)

  runOnFiles: (files, options, cb) ->
    console.log green("Running #{@name} on #{files.length} files")
    async.filter files, @hasChanged, (changedFiles) =>
      unchangedFiles = _.without(files, changedFiles)

      if @batch
        if changedFiles.length > 0
          @execFunc changedFiles, options, (err) =>
            growl("#{@name}\n#{shortErr(err)}") if err
            return cb(err) if err
            async.forEach changedFiles, @updateMtime, cb
        else
          cb(null)
      else
        if changedFiles.length > 0
          x = (f, innerCb) =>
            @execFunc f, options, (err) =>
              growl("#{f}\n#{shortErr(err)}") if err
              return innerCb(err) if err
              @updateMtime(f, innerCb)
          async.forEach changedFiles, x, cb
        else
          cb(null)

  execFunc: (f, options, cb) ->
    try
      @func(f, @calculateDest(f), options, cb)
    catch err
      cb(err)

  clean: (cb) ->
    @findSrcFiles (err, files) =>
      return cb(err) if err
      @cleanForFiles(files, cb)

  cleanForFiles: (srcFiles, cb) ->
    async.forEach srcFiles, @clearMtime, (err) =>
      return cb(err) if err
      destFiles = _.uniq(_.flatten(_.map(srcFiles, @calculateDest)))
      async.forEach destFiles, rm, cb


# queue up tasks and run one at a time
class RunQueue
  constructor: () ->
    @running = false
    @queue   = []

  add: (mapping, paths) ->
    if found = _.find(@queue, (e) -> e[0] is mapping)
      found[1] = _.uniq(found[1].concat(paths))
    else
      @queue.push([mapping, paths])

    unless @running
      clearTimeout(@startRunTimer) if @startRunTimer
      @startRunTimer = setTimeout(@run, 50)

  run: () =>
    clearTimeout(@startRunTimer) if @startRunTimer
    if @queue.length > 0
      @running = true
      [m, paths] = @queue.shift()
      m.runOnFiles(paths, {}, @run)
    else
      @running = false

_runQueue = new RunQueue()


# watch one or more files or directory trees, and call eventHandler if anything
# changes (or is added or removed)
class Watcher
  constructor: (@paths, @eventHandler) ->
    @watcher = null

  start: (cb = noop) ->
    gaze @paths, { interval: 250 }, (err, @watcher) =>
      @watcher.on "all", (event, filepath) =>
        filepath = filepath.replace("#{_cwd}\/", "")
        @eventHandler(event, filepath)

  stop: (cb = noop) ->
    @watcher?.close()
    cb(null)
