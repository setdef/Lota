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

Run it with `lota run path/to/game`, or `lota run` from inside the folder. Arguments after the folder reach `Lota.load`. Lota opens the modules and the window your settings ask for, in the order LÖVE's `boot.lua` does, then runs `Lota.run`, translated from `love.run`: each frame handles queued events, calls `update(dt)`, clears the window to the background color, calls `draw`, and shows the result. Every callback is optional, and each receives only as many of LÖVE's arguments as it declares. `lota` is always there, so `lota.graphics` and `def lota.update(dt)` read as a LÖVE tutorial's `love.graphics` and `function love.update(dt)` do.

An error in your game ends the program with Ruby's own backtrace. LÖVE draws an error screen instead; Lota's has not been designed yet.

## Development

Clone with submodules. `vendor/love` holds the LÖVE source Lota builds against, and `vendor/love-apple-dependencies` holds the prebuilt libraries LÖVE links on macOS (SDL3, FreeType, HarfBuzz, OpenAL Soft, and the rest):

```bash
git clone --recurse-submodules <repository>
bin/setup
bundle exec rake
```

`bin/setup` installs the pinned tools from `mise.toml`, CMake, Ninja, clang-format, and clang-tidy among them. `bundle exec rake` builds LÖVE's engine and the `Lota::Native` extension into `tmp/engine/build`, runs the tests (the native ones a second time under AddressSanitizer and UndefinedBehaviorSanitizer), then runs the C++ gates over Lota's own C++ in `ext/`. A clean run takes about four minutes, most of it compiling the engine twice; a run with nothing to rebuild takes under a minute. To work on the native side alone:

- `bundle exec rake compile` builds the engine and the extensions and copies `Lota::Native` to `lib/lota/native.bundle`. rake-compiler runs `ext/lota/extconf.rb`, which configures the CMake project in `ext/lota` and writes a Makefile that builds it; `gem install` runs the same script. CMake decides what to rebuild, so `rake compile` always calls it, and a build with no changes takes a second or two.
- `bundle exec rake test:native` rebuilds everything with ASan and UBSan into `tmp/sanitize/build` and runs `test/native`, `test/lovetest`, and `test/sanitizers` against it. ASan has to be in the Ruby process before anything it instruments, so the task starts Ruby directly with `DYLD_INSERT_LIBRARIES`; a shell or a binstub in between would drop it, because macOS removes `DYLD_` variables when it starts a protected binary such as `/bin/sh`. `test/sanitizers` holds deliberate memory bugs, and only this task runs it.
- `bundle exec rake engine:sources` regenerates `ext/lota/engine/sources_macos.cmake`, the list of LÖVE sources the engine compiles, after a bump of `vendor/love`. `rake engine:sources:check` fails until you do, so review the difference before you commit it.
- `bundle exec rake cpp` runs `cpp:format`, `cpp:no_nolint`, and `cpp:tidy`; `rake cpp:format:fix` rewrites the layout clang-format reports.

Bindings live in `ext/lota/native`. Each one includes `native/binding.hpp`, never Rice's own header, because `binding.hpp` is where every `love::Object` gets LÖVE's memory model (ADR 001, section 5): a Ruby wrapper holds one reference from the moment Ruby wraps the object until the garbage collector frees the wrapper. `ext/lota/native_test` is a test-only extension, `LotaNativeTest`, that the tests load from the build tree; the gem never packages it. `Lota::Native` has no RBS generator yet, so its signatures in `sig/lota/native.rbs` are written by hand, and `rbs:parity` checks them against the compiled extension.

Graphics and window calls run only on the process's main thread, as LÖVE keeps `love.graphics` and `love.window` there, and raise `ThreadError` anywhere else. Ruby's garbage collector can free a wrapper on any thread, so a wrapper of a graphics or window object freed off the main thread hands its reference to a release queue, which the main thread drains with `Lota::Native.drain_release_queue` (and at exit). Every class bound from those two modules belongs in `ReleasedOnMainThread` in `binding.hpp`.

`test/lovetest` holds LÖVE's own Lövetest tests (`vendor/love/testing`), translated to Ruby by ADR 001's rules and marked as Zlib snippets. They open a real window, as Lövetest does: SDL's offscreen driver cannot create a Metal or OpenGL context on macOS, so run them in a logged-in session. Each compares what Lota draws with LÖVE's expected image, by Lövetest's own rule.

## Copyright & License

Lota is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](vendor/love/license.txt).

Lota is an independent project. It is not made, endorsed, or supported by the LÖVE Development Team. It builds a modified version of LÖVE's engine (Zlib, © LÖVE Development Team), as described in [ADR 001](doc/contributors/adr/001.md).
