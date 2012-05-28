pie
===

```pie``` is a build tool for [Node.js](http://nodejs.org/)-based projects. It's similar to [Cake](http://coffeescript.org/#cake), but adds **smart dependency tracking** so only the files that need to get rebuilt will be (like good old [Make](http://www.gnu.org/software/make/)).

If you're experiencing pain using Cake or Rake or even Make for large JS projects, ```pie``` may just be your answer.

Features
--------

* Flexible DSL for defining exactly the tasks and build targets you need (loose superset of Cake syntax)
* Smart dependecy tracking for _fast_ incremental builds
* Built-in auto-watch with smart recalculation of changes
* Customizable command-line switches
* Fast in-VM compilation of CoffeeScript, LESS, andHandlebars files (and very easy to add new ones)
* Very fast for running ```git bisect`` on large projects due to fast incremental builds
* Growl notifications for build completion & errors

Installation
------------

```
$ npm install pie -g
```

Usage
-----

### Create a ```Piefile```

For a very simple one, see the ```Piefile``` for this project: http://github.com/kenpratt/pie/blob/master/Piefile

### Run a build

```
$ pie
```

### Start a watcher (will keep running, watching for changes and re-compiling files as needed)

```
$ pie watch
```

If you get ```Error: watch EMFILE```, try increasing your open file discriptor limit. You can add this to your ```.bashrc``` or ```.zshrc``` to have it apply on boot.

```
$ ulimit -n 1024
```

### List tasks

```$ pie -T```

Copyright
---------

Copyright (c) 2012 Ken Pratt. See LICENSE for details.
