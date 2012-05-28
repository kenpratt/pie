fs            = require "node-fs"
path          = require "path"
CoffeeScript  = require "coffee-script"
less          = require "less"
Handlebars    = require "handlebars"

# CoffeeScript compiler
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

# LESS compiler
exports.less = (src, dest, options, cb) ->
  console.log "Compiling", src
  fs.readFile src, "utf-8", (err, code) ->
    return cb(err) if err
    parser = new(less.Parser)({ paths: [path.dirname(src)], filename: src })
    parser.parse code, (err, tree) ->
      less.writeError(err) if err
      return cb(err) if err
      try
        res = tree.toCSS({})
        fs.mkdirSync path.dirname(dest), 0o0755, true
        fs.writeFile dest, res, cb
      catch err
        cb(err)

# Handlebars compiler
exports.handlebars = (src, dest, options, cb) ->
  console.log "Compiling", src
  fs.readFile src, "utf-8", (err, code) ->
    return cb(err) if err
    try
      res = Handlebars.precompile(code, {})
      res = "define([], function() { return Handlebars.template(\n" + res + "); });\n"
      fs.mkdirSync path.dirname(dest), 0o0755, true
      fs.writeFile dest, res, cb
    catch err
      cb(err)
