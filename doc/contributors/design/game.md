<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# How a Lota Game Is Laid Out and Run

A LÖVE game is a folder. Its `main.lua` defines callbacks as functions on the global `love` table (`function love.update(dt)`). An optional `conf.lua` defines `love.conf(t)`, which LÖVE calls with a table of settings before it loads any module or opens the window (`vendor/love/src/modules/love/boot.lua`, lines 178–256). `love.run` then calls each callback that exists and skips the rest (`callbacks.lua`).

A Lota game is laid out the same way, in Ruby ([ADR 009](../adr/009.md)). This document says how a game is found, configured, called, and restarted, and where it saves.

## A game is a folder

A game is a folder holding `main.rb` and, optionally, `conf.rb`. `lota run` runs the game in the current folder, or in the folder given (`lota run path/to/game`), as `love path/to/game` does. It runs in the order `boot.lua` does:

1. Load `conf.rb`, if present.
2. Call `Lota.conf` with the settings.
3. Bring up the modules and the window.
4. Load `main.rb`.
5. Run the loop.

## The loop is LÖVE's, in Ruby

`love.run`, callback dispatch, error handling, and the boot sequence are Lua in LÖVE: `modules/love/boot.lua` and `callbacks.lua`. When `load`, `update`, `draw`, and `errorhandler` run, and in what order, is part of LÖVE's behavior. Lota ports those files to Ruby line by line, with SPDX snippet markers (`Zlib`) on the ported code.

## Callbacks are methods on `Lota`

Where Lua defines a function on the `love` table, Ruby defines a method on the `Lota` module:

```ruby
# conf.rb
def Lota.conf(t)
  t.title = "Sample Game"
  t.window.width = 1280
  t.window.fullscreentype = :exclusive
  t.modules.physics = false
end

# main.rb
def Lota.update(dt)
  return if paused
  player.move(dt)
end
```

Ruby methods do everything LÖVE code does with its callbacks:

| LÖVE | Lota |
|---|---|
| `function love.update(dt)` | `def Lota.update(dt)` |
| `love.draw()` | `Lota.draw` |
| `if love.update then` | `if Lota.respond_to?(:update)` |
| `return` inside a callback | `return` inside the method |
| saving and wrapping `love.update` | prepending a module to `Lota.singleton_class` and calling `super` |

A game-state library for Lota wraps callbacks with `prepend` where a Lua one reassigns a table field.

## A callback gets the arguments it declares

Lua passes a callback every argument LÖVE has, and the callback ignores the ones it does not declare: `function love.keypressed(key)` receives three. Lota's loop passes as many of LÖVE's arguments as the method declares, so `def Lota.keypressed(key)` receives the key alone.

- A method that takes a splat receives them all.
- A required parameter LÖVE does not pass receives `nil`, as Lua pads missing arguments with `nil`.
- An optional parameter LÖVE does not pass keeps the default its author wrote. Lua has no defaults to follow, and Ruby the language comes first.
- LÖVE passes no keywords, so a keyword parameter needs a default.

A game that calls its own callback calls an ordinary Ruby method, with Ruby's usual argument checks.

## `lota` is always there

Lota defines a private `Kernel#lota` that returns `Lota`, as Ruby's own `puts` and `require` are private `Kernel` methods. Each module has a lowercase accessor: `Lota.graphics` returns `Lota::Graphics`. So a tutorial's `love.` becomes `lota.` and nothing else changes: `def lota.update(dt)`, `lota.graphics.rectangle(...)`.

Being private, `lota` adds no method to other objects' public interfaces. Its only cost is reserving the name everywhere, as `puts` does. The core API therefore has two spellings for the same modules. `Lota::Graphics.rectangle(...)` stays the idiomatic one, by translation rule 1 ([translation.md](translation.md)).

A module the settings turn off is `nil` through its accessor (`lota.timer` with `t.modules.timer = false`), as `love.timer` is `nil` in LÖVE.

## The settings keep LÖVE's names

`t` has a reader and a writer for each of `boot.lua`'s settings, nested as in Lua (`t.window.width`).

- Enum strings become symbols, by translation rule 9.
- LÖVE's settings names are lowercase words run together (`fullscreentype`, `minwidth`, `usedpiscale`). Translation rule 13 converts only camelCase, so they keep LÖVE's spelling.
- A setting LÖVE does not know is accepted and ignored, as LÖVE ignores unknown keys in its table. A translated `conf.lua` with keys of its own still runs.
- Reading a setting that was never set returns `nil`, as reading a missing key does in Lua.

## `require` looks in the game folder

`lota run` puts the game folder on `$LOAD_PATH`, as LÖVE's `require` searches the game's own folder. It leaves the working directory alone, as LÖVE does.

## Errors show LÖVE's error screen

When game code raises, Lota does what LÖVE's `love.errorhandler` does (`boot.lua` and `callbacks.lua`). It shows LÖVE's error screen in the game's window, with the error and a Ruby backtrace where LÖVE shows a Lua traceback. A game may define `Lota.errorhandler` to replace it, as a LÖVE game may define `love.errorhandler`.

## Where a game saves

LÖVE keeps a game's saved files in the system's application data folder, under the game's identity (`t.identity`). When the game runs through the `love` program rather than fused into an app of its own, LÖVE adds a folder named after itself (`Filesystem.cpp:608-611`, `Filesystem.h:40`).

- A fused game saves exactly where LÖVE's fused game does, so a player finds the same folder for either. `lota fuse` puts the game in a folder named for its identity, so a game without `t.identity` does not save under Fledge's `app` folder name ([packaging.md](packaging.md)).
- Under `lota run`, Lota's counterpart of the `love` program, the added folder is `Lota`, and `lota` on Linux, lowercase as LÖVE's `love` is there. Naming it after LÖVE would put LÖVE's name in Lota's own product (AGENTS.md, Trademarks). `ext/lota/engine/appdata_folder.h` sets it without changing LÖVE's files.
- Under the macOS App Sandbox a game saves in its container, `~/Library/Containers/IDENTIFIER/Data/Library/Application Support/<identity>`, as a sandboxed LÖVE game does.

## Restarting

`Lota::Event.restart` queues LÖVE's quit message with `"restart"` first. LÖVE then runs the game again in the same program, with the same arguments, and passes the value on as `love.restart` (`src/love.cpp`, `runlove` and `main`). Lota restarts in every case LÖVE does, by `exec` ([ADR 012](../adr/012.md)):

- The game ends as a quit ends it, with the window closed and the exit procs run.
- `lota run` replaces its process with itself, with the same arguments. It remembers `$0`, so a restart under `bundle exec` runs Lota again rather than `bundle`.
- A fused game runs the program the process runs, with the same arguments. That program is Fledge's launcher, found as LÖVE's `getExecutablePath` finds it, so the app sets itself up as it did the first time. Only when the program is Ruby's own, as when someone runs the entry script with `ruby`, does the game start again through Ruby and the script.
- On Windows, Ruby's `exec` starts a new process and waits for it. Each run has its own process id, and the process that restarted stays, with any audio device it opened, until the new run ends.
- The new process reads the value as `Lota.restart`. It crosses in an environment variable, `Lota::Restart::VARIABLE`, that holds `nil`, `true`, `false`, a number, a String, or an Array or Hash of them, and nothing in it is evaluated.
- A phone cannot replace its process, and a game started any other way, such as by `Lota::Boot` in your own program, ends when it restarts, as a quit ends it.
