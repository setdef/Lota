<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Lota

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

Lota lets you make 2D games in Ruby. It is an independent project, not made, endorsed, or supported by the LÖVE Development Team. It builds a modified version of the C++ engine that [LÖVE](https://love2d.org) games run on and drives it from Ruby instead of Lua, so a game behaves the same in both, and a LÖVE tutorial still reads true once its calls are translated by a handful of rules.

The name comes from the Lota Bowl, a classic Indian magic trick: the magician empties a brass vessel, and it fills itself again, and again, as often as it is poured out. A game loop does the same, every frame.

Lota is a plan, not yet a gem you can install. Contributors start with [ADR 001](doc/contributors/adr/001.md), which records what Lota is and why, and [Plan 001](doc/contributors/plan/001.md), which orders the work.

## Running a game

A Lota game is a folder, as a LÖVE game is ([ADR 003](doc/contributors/adr/003.md)). `main.rb` defines the game's callbacks as methods on `Lota`, and an optional `conf.rb` changes its settings before the window opens:

```ruby
# conf.rb
def Lota.conf(t)
  t.window.title = "My Game"
  t.window.width = 640
  t.window.height = 480
end

# main.rb
def Lota.load
  @x = 0
end

def Lota.update(dt)
  @x = (@x + 120 * dt) % Lota::Graphics.width
end

def Lota.keypressed(key)
  Lota::Event.quit if key == :escape
end
```

Run it with `lota run path/to/game`, or `lota run` from inside the folder. Arguments after the folder reach `Lota.load`. Lota opens the modules and the window your settings ask for, in the order LÖVE's `boot.lua` does, then runs `Lota.run`, translated from `love.run`: each frame handles queued events, calls `update(dt)`, clears the window to the background color, calls `draw`, and shows the result. Every callback is optional, and each receives only as many of LÖVE's arguments as it declares, with `nil` for a required parameter beyond them, as in Lua, while an optional parameter keeps its default. Numbers LÖVE holds as integers, such as a mouse button or a resized window's size, arrive as Integers, and the rest as Floats. `lota` is always there, so `lota.graphics` and `def lota.update(dt)` read as a LÖVE tutorial's `love.graphics` and `function love.update(dt)` do; as in LÖVE, `lota.timer` is `nil` when your settings turn the timer off (`t.modules.timer = false`). Settings LÖVE does not know are accepted and ignored, as LÖVE ignores keys it does not read, and a setting never set reads as `nil`, as a missing key does in Lua. `Lota::Event.poll` returns an Enumerator of the queued events, or takes a block, where LÖVE's returns an iterator for Lua's `for`, and an exit status such as `Lota::Event.quit(3)`'s is an Integer. Every engine object answers `type` with LÖVE's name for its type (`"Texture"`) and `type_of?` for that type and its parents (`"Object"`), as LÖVE's `type` and `typeOf` do. The game's folder is on `$LOAD_PATH`, so `require "player"` loads the `player.rb` beside `main.rb`, and the working directory stays where you ran `lota run`. Files your game names are read from its folder too, as LÖVE's filesystem reads them, so `Lota::Graphics::Font.new("assets/pixel.ttf", 16)` finds the font in the game's `assets` folder wherever you started it.

An error in your game shows LÖVE's error screen in its window, as LÖVE's `love.errorhandler` does ([ADR 003](doc/contributors/adr/003.md), section 7): the error and its Ruby backtrace, where LÖVE shows a Lua traceback, in white on LÖVE's blue, until you press Escape or close the window, which exits with 1. Ctrl+C copies the error. The error and its backtrace are printed too. Define `Lota.errorhandler(error)` to replace the screen, as a LÖVE game defines `love.errorhandler`: it receives what your game raised, and returns a frame for Lota to call until the frame returns an exit status, or `nil` to exit with 1.

## Development

Clone with submodules. `vendor/love` holds the LÖVE source Lota builds against, and `vendor/love-apple-dependencies` holds the prebuilt libraries LÖVE links on macOS (SDL3, FreeType, HarfBuzz, OpenAL Soft, and the rest):

```bash
git clone --recurse-submodules https://github.com/setdef/lota.git
bin/setup
bundle exec rake
```

`bin/setup` installs the pinned tools from `mise.toml`, CMake, Ninja, clang-format, and clang-tidy among them. `bundle exec rake` builds LÖVE's engine and the `Lota::Native` extension into `tmp/engine/build`, runs the tests (the native ones a second time under AddressSanitizer and UndefinedBehaviorSanitizer), then runs the C++ gates over Lota's own C++ in `ext/`. A clean run takes about six minutes, most of it compiling the engine twice and building the reference `love` the parity harness compares Lota with; a run with nothing to rebuild takes under a minute. To work on the native side alone:

- `bundle exec rake compile` builds the engine and the extensions and copies `Lota::Native` to `lib/lota/native.bundle`. rake-compiler runs `ext/lota/extconf.rb`, which configures the CMake project in `ext/lota` and writes a Makefile that builds it. The source gem's `gem install` runs the same script, which stops there, since the gem ships no LÖVE sources, and names the precompiled gem. CMake decides what to rebuild, so `rake compile` always calls it, and a build with no changes takes a second or two.
- `bundle exec rake test:native` rebuilds everything with ASan and UBSan into `tmp/sanitize/build` and runs `test/native`, `test/lovetest`, and `test/sanitizers` against it. ASan has to be in the Ruby process before anything it instruments, so the task starts Ruby directly with `DYLD_INSERT_LIBRARIES`; a shell or a binstub in between would drop it, because macOS removes `DYLD_` variables when it starts a protected binary such as `/bin/sh`. `test/sanitizers` holds deliberate memory bugs, and only this task runs it.
- `bundle exec rake engine:sources` regenerates `ext/lota/engine/sources_macos.cmake`, the list of LÖVE sources the engine compiles, after a bump of `vendor/love`. `rake engine:sources:check` fails until you do, so review the difference before you commit it.
- `bundle exec rake bindings:generate` writes the bindings `ext/lota/bindings.rb` lists from LÖVE's `wrap_*.cpp` files, by ADR 001's rules and the names `binding_exceptions.rb` records, into `ext/lota/native/generated` and `sig/lota/native/generated.rbs` (`tasks/bindings`). Those files are never edited by hand. `rake bindings:check` fails, before the engine builds, until the committed files match what the generator writes. `rake "bindings:report[tmp/report.txt]"` lists every LÖVE function that fits no rule, fits several, or leaves a rule's decision open, and every function the parser cannot read, each with its file, line, and why.
- `bundle exec rake package:native` builds the precompiled gem, `pkg/lota-<version>-arm64-darwin.gem`, from `rake compile`'s bundle (`tasks/native_gem.rb`). It carries the bundle, the frameworks it loads (SDL3, FreeType, and HarfBuzz so far, arm64 only and without headers) in `lib/lota/frameworks`, and a record of who wrote them under which licenses, by the REUSE Specification as the repository is: its `REUSE.toml` is the repository's with an annotation for the bundle and one for each framework, written from `ext/lota/licenses.rb`, and its `LICENSES` holds the text of every license its files use, the ones only the gem uses coming from `ext/lota/licenses`. The bundle's annotation names the libraries the linker put in it, which the build reads from the linker's map (`lib/lota/native.map` in the build tree) and ninja's dependency log. The bundle's rpaths, which point into `vendor/`, are replaced by `@loader_path/frameworks`, and the bundle and every framework are signed again ad hoc and verified with `codesign --verify --strict`. A framework, or a file the bundle was compiled from, that `ext/lota/licenses.rb` does not record stops the build, and so does a gem `reuse lint` does not call compliant.
- `bundle exec rake package:check` checks that the source gem's `gem install` stops with that message, then runs `reuse lint` on the precompiled gem's unpacked package and loads the gem from it. `rake package:install` builds the precompiled gem as `package:native` does, then delivers it as `rake "package:deliver[path/to/lota-<version>-arm64-darwin.gem]"` delivers a gem built elsewhere: it installs the gem into an empty `GEM_HOME` that sees no other gem, runs `lota --version`, and runs `lota run` on two games: one that opens a window and quits with a status of its own, and `test/lovetest/game`, which runs the translated Lövetest tests against LÖVE's expected images, with Minitest installed beside the gem. Each run must end with its expected status and output, load Lota, its bundle, and SDL3 only from the installed gem, and load nothing from the repository's `lib/`, which a guard loaded into the run checks. `package:deliver` builds nothing, so it runs where the gem was never built. Both checks fail on any warning `gem build` prints. They take seconds, and `bundle exec rake` runs `package:check` and `package:install`.
- `bundle exec rake cpp` runs `cpp:format`, `cpp:no_nolint`, and `cpp:tidy`; `rake cpp:format:fix` rewrites the layout clang-format reports.
- `bundle exec rake lint:workflows` checks `.github/workflows` with actionlint, and each step's script with shellcheck. Both are pinned in `mise.toml`, and the task fails without shellcheck, which actionlint would skip without a word.

GitHub Actions runs `.github/workflows/ci.yml` on every push and pull request, on GitHub's Apple Silicon runners with macOS 15 (`macos-15`), whose session is logged in, so the tests open real windows there as on your Mac. The **Gate** job installs the Ruby that `mise.toml` pins with `ruby/setup-ruby` and the other tools in `mise.toml` with mise, runs `bundle exec rake`, fails if the gate changed a file (its `lint:fix` step corrects what it can, which would otherwise pass unnoticed), and builds the precompiled gem with `rake package:native` as an artifact. Compiled objects come from ccache, which reuses one only when the compiler, its arguments, and every file it reads are the same. The **Delivery** job then downloads that gem on a fresh runner that builds nothing and fetches only `vendor/love`, for LÖVE's expected images, installs the same Ruby, and runs `rake package:deliver` on it, so the walking skeleton's acceptance test, Lövetest's `love.test.graphics.clear`, passes from the installed gem. CI's Ruby comes from `ruby/setup-ruby` rather than mise because mise's precompiled Ruby for macOS, from `jdx/ruby`, is built without ZJIT, which `rake bench` measures; setup-ruby's is built by ruby-build with Rust, as a Ruby that mise compiles is. The **Accessibility probe** job records whether a runner lets a script press Return on another process's dialog through System Events, as the harness will to dismiss LÖVE's dialogs; it never fails, and its answer, "allowed" or "denied", is a notice on the run and in the job's summary.

Bindings live in `ext/lota/native`. Each one includes `native/binding.hpp`, never Rice's own header, because `binding.hpp` is where every `love::Object` gets LÖVE's memory model (ADR 001, section 5): a Ruby wrapper holds one reference from the moment Ruby wraps the object until the garbage collector frees the wrapper. `ext/lota/native_test` is a test-only extension, `LotaNativeTest`, that the tests load from the build tree; the gem never packages it. `Lota::Native` has no RBS generator yet, so its signatures in `sig/lota/native.rbs` are written by hand, and `rbs:parity` checks them against the compiled extension.

Graphics and window calls run only on the process's main thread, as LÖVE keeps `love.graphics` and `love.window` there, and raise `ThreadError` anywhere else. Ruby's garbage collector can free a wrapper on any thread, so a wrapper of a graphics or window object freed off the main thread hands its reference to a release queue, which the main thread drains with `Lota::Native.drain_release_queue` (and at exit). Every class bound from those two modules belongs in `ReleasedOnMainThread` in `binding.hpp`.

`test/parity` is the parity harness (Plan 001): it runs a published LÖVE game, unchanged, in a reference `love` built from `vendor/love`, and the game's Ruby translation in Lota, both with a fixed `dt` and the same scripted keys, and compares every frame the two show by Lövetest's rule. The games are pinned submodules under `test/fixtures` (the arkanoid tutorial and Gravity-Wars), which Lota's lint and REUSE checks and the gem leave out, as they leave out `vendor/`; their translations live in `test/games`. `test/parity/lua/conf.lua` is the harness's side in LÖVE: it mounts the game, wraps `love.update` to hold keys in SDL's keyboard state and pass the fixed `dt`, and wraps `love.draw` to save each frame with `love.graphics.captureScreenshot`. Random numbers come from LÖVE's own generator on both sides, as Plan 001 has them: the Lua side points `math.random` and `math.randomseed` at `love.math.random` and `love.math.setRandomSeed`, which `Lota::Math.random` and `random_seed=` port, and both sides fix the clock a game seeds from, `os.time()` in Lua and `Time.now` in Ruby, at the script's `clock`, so a game that seeds from the time draws the same numbers in both. Where a game needs a key press rather than a held key, as on Escape to quit, the script presses it: both sides also push SDL's key down and key up events into SDL's queue with `SDL_PushEvent`, which LÖVE's own event code turns into `keypressed` and `keyreleased`, and which, unlike a key macOS reports, does not need the window to have keyboard focus. `test/parity/probe.rb` does the same in Lota, loaded with `ruby -r` into `lota run`, and compares each frame with LÖVE's as it goes, reporting the first that differs and the pixel where. `bundle exec rake test:parity` runs it, after `rake reference:love` builds the reference into `tmp/reference` with LÖVE's own macOS CI commands (`xcodebuild` archive and export, read from `vendor/love/.github/workflows/main.yml`), compiling through ccache when it is on the `PATH`. That build needs Xcode itself, not only its command line tools. A clean build takes about two minutes, a build from ccache about 25 seconds, and a build of the same commits nothing. `bundle exec rake` runs both.

`test/lovetest` holds LÖVE's own Lövetest tests (`vendor/love/testing`), translated to Ruby by ADR 001's rules and marked as Zlib snippets. They open a real window, as Lövetest does: SDL's offscreen driver cannot create a Metal or OpenGL context on macOS, so run them in a logged-in session. Each compares what Lota draws with LÖVE's expected image, by Lövetest's own rule.

## Copyright & License

Lota is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](vendor/love/license.txt).

Some parts of this program, and of its precompiled gem, come from other sources under their own licenses, and their copyright belongs to their owners. Each file says which, by the [REUSE Specification – Version 3.3](https://reuse.software/spec-3.3/). The precompiled gem's `REUSE.toml` records them for the compiled extension, which holds LÖVE's engine and the libraries LÖVE bundles, and for each framework the gem carries, and its `LICENSES` folder holds their texts.

The precompiled gem carries FreeType, which it uses under the [FreeType License](ext/lota/licenses/LICENSE-FTL.txt). As that license asks of a binary distribution: the software is based in part of the work of the FreeType Team.

Lota is an independent project. It is not made, endorsed, or supported by the LÖVE Development Team. It builds a modified version of LÖVE's engine (Zlib, © LÖVE Development Team), as described in [ADR 001](doc/contributors/adr/001.md).
