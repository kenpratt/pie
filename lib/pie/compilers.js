(function() {
  var CoffeeScript, Handlebars, fs, less, path;

  fs = require("node-fs");

  path = require("path");

  CoffeeScript = require("coffee-script");

  less = require("less");

  Handlebars = require("handlebars");

  exports.coffee = function(src, dest, options, cb) {
    console.log("Compiling", src);
    return fs.readFile(src, "utf-8", function(err, code) {
      var res;
      if (err) {
        return cb(err);
      }
      try {
        res = CoffeeScript.compile(code, {});
        fs.mkdirSync(path.dirname(dest), 0x1ed, true);
        return fs.writeFile(dest, res, cb);
      } catch (err) {
        return cb(err);
      }
    });
  };

  exports.less = function(src, dest, options, cb) {
    console.log("Compiling", src);
    return fs.readFile(src, "utf-8", function(err, code) {
      var parser;
      if (err) {
        return cb(err);
      }
      parser = new less.Parser({
        paths: [path.dirname(src)],
        filename: src
      });
      return parser.parse(code, function(err, tree) {
        var res;
        if (err) {
          less.writeError(err);
        }
        if (err) {
          return cb(err);
        }
        try {
          res = tree.toCSS({});
          fs.mkdirSync(path.dirname(dest), 0x1ed, true);
          return fs.writeFile(dest, res, cb);
        } catch (err) {
          return cb(err);
        }
      });
    });
  };

  exports.handlebars = function(src, dest, options, cb) {
    console.log("Compiling", src);
    return fs.readFile(src, "utf-8", function(err, code) {
      var res;
      if (err) {
        return cb(err);
      }
      try {
        res = Handlebars.precompile(code, {});
        res = "define([], function() { return Handlebars.template(\n" + res + "); });\n";
        fs.mkdirSync(path.dirname(dest), 0x1ed, true);
        return fs.writeFile(dest, res, cb);
      } catch (err) {
        return cb(err);
      }
    });
  };

}).call(this);
