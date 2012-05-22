fs           = require "node-fs"
path         = require "path"
CoffeeScript = require "coffee-script"
glob         = require "glob"
nStore       = require "nstore"
_            = require "underscore"

_mappings = []
_mtimes = null

load = (cb) ->
  _mtimes = nStore.new(".pie.db", cb)

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

# build target for coffeescript files
map "src/**/*.coffee",
    (src) -> src.replace(/^src\/(.+)\.coffee$/, "lib/pie/$1.js"),
    (src, dest, cb) ->
      console.log "compiling coffee", src, dest
      fs.readFile src, (err, code) ->
        return cb(err) if err
        res = CoffeeScript.compile(code.toString(), {})
        fs.mkdirSync path.dirname(dest), 0o0755, true
        fs.writeFile dest, res, cb

load () ->
  _.each _mappings, (m) ->
    console.log "running mapping", m
    glob m.src, {}, (err, files) ->
      return console.log("[ERROR]", err) if err
      console.log "found files", m.src, files
      _.each files, (f) ->
        hasChanged f, (err, changed) ->
          return console.log("[ERROR]", f, err) if err
          if changed
            m.run f, m.dest(f), (err) ->
              return console.log("[ERROR]", f, err) if err
              updateMtime f, (() -> console.log "finished", f)
          else
            console.log "skipping", f
