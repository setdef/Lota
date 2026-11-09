<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# How Lota Builds and Binds LÖVE's Engine

Lota runs LÖVE's own C++ engine and replaces only the Lua around it ([ADR 004](../adr/004.md)). This document says how: which of LÖVE's sources Lota compiles, how it changes them, how Ruby holds engine objects, and which threads and Ractors may touch them.

## The pinned engine

LÖVE's engine is the submodule `vendor/love`, pinned to commit `b7daef0f7` on LÖVE's `main` branch, from 2026-09-20. LÖVE 12.0 is unreleased. The pin makes an update deliberate: its behavior changes get reviewed rather than arriving whenever upstream moves.

Everything LÖVE links, Lota links, each at the version LÖVE builds against. From outside LÖVE's tree that means SDL3, FreeType, HarfBuzz, OpenAL Soft, Vorbis, Ogg, Theora, ModPlug, and zlib. From `src/libraries` it means Box2D 2.4, PhysicsFS, glslang, SPIRV-Cross, and the rest.

A contributor builds those dependencies as LÖVE's own CI does: from `love2d/love-apple-dependencies` on macOS, and with `love2d/love-appimage-source`'s Makefile on Linux. A player or game developer installs a precompiled gem and compiles nothing (see [packaging.md](packaging.md)).

To upgrade LÖVE, bump the submodule, regenerate the source lists and the bindings, update the patches, and rerun every parity test.

## The source lists

LÖVE's `CMakeLists.txt` builds each module as a static library whose sources include its `wrap_*.cpp` files, so none of those targets links without Lua. Lota lists LÖVE's sources itself instead. `rake engine:sources` evaluates LÖVE's `CMakeLists.txt` for each platform and writes `ext/lota/engine/sources_<platform>.cmake`, less these files:

- every `wrap_*.cpp` file;
- `common/runtime.*` and `common/Reference.*`, the Lua glue;
- `modules/love`, the Lua boot sequence;
- `modules/thread`'s Lua threads and channels (`LuaThread.*`, `ThreadModule.*`, `Channel.*`), keeping its mutex and thread primitives (`threads.*`, `Thread.h`, `sdl/`), which the rest of the engine includes;
- `libraries/enet/enet.cpp`, the lua-enet binding, keeping the enet C library beside it;
- `love.cpp`, the `love` program's `main`;
- the Lua libraries LÖVE bundles: `libraries/lua53`, `libraries/luasocket`, and `libraries/luahttps`.

The engine builds as one static library. LÖVE's sources compile with warnings off (`-w`), since their warnings are LÖVE's to fix. Lota's own C++ compiles with `-Wall -Wextra -Werror`.

## Patch files

Lota changes LÖVE's engine only where its own code cannot do the work, and then as little as it can ([ADR 005](../adr/005.md)). Each change is a patch file in `ext/lota/engine/`. When CMake configures, it copies the files a patch touches into the build tree, applies the patch to the copy, and compiles the copy in place of `vendor/love`'s file. It copies again whenever a patch or a file it patches changes, and writes a patched file only when it differs, so an unchanged file does not rebuild. Nothing ever writes to `vendor/love`.

Each patch:

- states in its header why nothing outside LÖVE's file can do the work;
- is dropped once LÖVE no longer needs it;
- has, when it fixes a defect in LÖVE, the report Lota would file upstream beside it in `doc/contributors/upstream/`.

The list of patches lives in `ext/lota/engine/`, not here. Their number and size are worth keeping small and worth measuring. A fork of LÖVE is a different decision, and the maintainer makes it.

## Bindings

The bindings use [Rice](https://github.com/ruby-rice/rice) 4.12.0 ([ADR 006](../adr/006.md)). Rice binds C++ classes to Ruby with no third language between Ruby and LÖVE.

LÖVE's `wrap_*.cpp` files are the specification for each binding: its arity, overloads, defaults, and error messages. Names and call shapes come from the translation rules ([translation.md](translation.md)). The binding generator in `tasks/bindings/` writes every binding it can. A binding that stays hand-written records why in `ext/lota/bindings.rb`.

## The memory model

Every engine object (Texture, Source, Body, Font) inherits from `love::Object`, which counts references with a `std::atomic<int>`. A Ruby wrapper retains its object when Ruby creates the wrapper, and releases it when Ruby's garbage collector frees the wrapper. One rule covers every class, so there is one place to get it right.

Ruby's collector frees a wrapper on whichever thread triggered the collection. Lua collects only on LÖVE's main thread. So objects of the modules LÖVE confines to the main thread, `love.graphics` and `love.window`, are not released where Ruby frees them. Their release joins a queue that the main thread drains once a frame, and once more when the program exits.

## Threads and Ractors

A game's callbacks run in the main Ractor, on the thread that started Ruby ([ADR 007](../adr/007.md)). LÖVE runs a game in one Lua state on its main thread, and SDL needs the main thread for windows and events on macOS.

Game code stays on the main thread even where a Ractor could hold it. `love.graphics` works on the main thread only, so graphics calls from another Ractor would have to be recorded and replayed, and every call that reads state back (`getColor`, `getCanvas`, `getStackDepth`) would answer from a stale copy.

Other Ractors take the part of `love.thread`:

- LÖVE decides what may leave the main thread. Its thread module forbids only `love.window` and `love.graphics` (`src/modules/thread/LuaThread.cpp`, lines 72–73). Lota marks those two modules Ractor-unsafe and the rest Ractor-safe.
- Engine objects cross Ractors as `love.thread`'s channels pass them between threads: by sharing one reference-counted object, never by copying it. Every `love::Data` subclass (`ImageData`, `SoundData`, `FileData`, `ByteData`, and the rest) guards itself with LÖVE's own lock (`src/common/Data.h`). So Lota marks their Ruby types `RUBY_TYPED_FROZEN_SHAREABLE` and freezes their wrappers. `Ractor.make_shareable` then shares them, and their methods keep working under that lock.
- Engine objects without such a lock, such as `Transform`, are never shareable. Neither are objects of the modules LÖVE confines to the main thread.
- Values that are not engine objects, such as the colors and positions the translation rules return as Arrays, are plain Ruby values, frozen when they cross Ractors.
- A debug mode checks `Ractor.shareable?` on everything sent between Ractors.

Ractors are still experimental in Ruby 4.0, so none of this is the default path yet.

## Binding cost

Through Rice a call costs about 0.4 to 0.85 µs, most of it Rice rebuilding its argument map on every call. The same draw costs about 50 ns in LÖVE. So 10,000 draws a frame take about 8 ms in Lota and 0.5 ms in LÖVE. The fixture games make 100 to 150 calls a frame, under 1% of a frame, and the heaviest, flash-blip, makes 1,300 to 2,600, 7 to 13%. `rake bench` measures it.

Lota keeps Rice for now. Binding through Ruby's C API directly costs a few nanoseconds a call, and the generator could emit it. Lota revisits that when a fixture game's binding cost becomes a problem.

Neither of Ruby's JITs sees into C++. A call into a C extension is a point the JIT cannot optimize through, though it discards no compiled code. YJIT is Ruby 4.0's production JIT. ZJIT is experimental in 4.0, inlines small Ruby methods into their callers, including methods that yield, and should make the block forms of translation rules 11 and 12 cheap. As the Ruby side gets faster, binding calls become a larger share of each frame, so the benchmark runs under both JITs.

LÖVE 12 batches draws internally, so Lota binds draw calls directly. A Ruby-side batcher gets built only if the benchmark says one is needed. SpriteBatch stays the documented way to draw many sprites, as in LÖVE.
