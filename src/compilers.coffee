fs            = require "node-fs"
path         = require "path"
CoffeeScript  = require "coffee-script"

# in-vm compilation of coffeescript files
exports.coffee = (src, dest, options, cb) ->
  console.log "Compiling", src
  fs.readFile src, "utf-8", (err, code) ->
    return cb(err) if err
    try
      res = CoffeeScript.compile(code, {})
      fs.mkdirSync path.dirname(dest), 0o0755, true
      fs.writeFile dest, res, cb
    catch err
      cb(err)
