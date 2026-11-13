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

Other Ractors take the part of `love.thread`. Each `Lota::Thread::Thread` runs its code in a Ractor of its own, as LÖVE runs each thread's code in a Lua state of its own. LÖVE's `Channel` and `LuaThread` hold Lua values, so Lota leaves them out of the engine (see "The source lists") and ports them to hold Ruby values (`ext/lota/native/thread.cpp`):

- The extension declares itself Ractor-safe (`rb_ext_ractor_safe`) before it defines any method, so other Ractors may call into every module. That needs Ruby 4.1, whose `rb_gc_register_address`, which Rice calls for every value it holds, keeps a list for each Ractor ([ADR 013](../adr/013.md)).
- LÖVE decides what may leave the main thread. Its thread module forbids only `love.window` and `love.graphics` (`src/modules/thread/LuaThread.cpp`, lines 71–73). Their bindings raise `ThreadError` off the main thread, in another Ractor as on another Ruby thread, and `lota.graphics` and `lota.window` are `nil` in a thread's code. Every other module answers there, the input modules too, as LÖVE lets a thread load them.
- A thread's Ractor runs LÖVE's `LuaThread::threadFunction` step for step (lines 50–115): it requires Lota, its thread module, and its filesystem, in the order LÖVE requires `love`, `love.thread`, and `love.filesystem`, then runs the code with its arguments. Ruby 4.1 runs a Ractor's `require` in the main Ractor, whose `$LOAD_PATH` holds the game's folder, so a thread's `require` finds the game's files, as `love.filesystem` makes it find them in LÖVE.
- Each Ractor keeps its own wrapper map, in Ractor-local storage, and its own wrappers, as each of LÖVE's Lua states keeps its own userdata. No wrapper is shared between Ractors. A release ends one Ractor's use of an object, as `w__release` clears one Lua state's proxy (`src/common/runtime.cpp`, lines 170–197), and the others go on using it.
- Engine objects cross Ractors as `love.thread`'s channels pass them between threads: as the same reference-counted object, never a copy, with no lock beyond LÖVE's. A message carries each engine object in a carrier Ractors share, which retains the object, and the Ractor that receives it wraps it anew, from its own map, wherever the object sits in the message. LÖVE's reference count is atomic (`src/common/Object.cpp`), so any thread may hold the object. LÖVE locks no object's state for its threads: a `love::Data` has a mutex, but only `performAtomic` and a few of the engine's readers take it (`src/common/Data.cpp`, lines 35–43), so a Data's bytes are as unguarded in Lota as in LÖVE, and a game that changes one object from two threads at once races in both.
- The Ruby values a game sets on an engine object, a Body's, Shape's, or Joint's user data and a World's callbacks and contact filter, are the one place Ruby forces Lota to differ from LÖVE. Ruby lets no Ractor touch an object of another's, and only the setting Ractor's collector marks the value. So such a value stays with the Ractor that set it (`ruby::Root`, `ext/lota/native/ruby.hpp`): another Ractor that reads it, or whose `World#update` would call it, raises `Ractor::IsolationError`, while the engine object itself goes on working there. In LÖVE the value lives in the registry of the Lua state that set it, so no other state uses it either.
- A Channel keeps a copy of each message, as LÖVE's keeps a `Variant`, and each `pop`, `demand`, and `peek`, and each thread's arguments, hand the receiver a fresh value: every String, Array, and Hash in it unfrozen, as LÖVE pushes a new table each time. Ruby keeps frozen only what Ractors share: the carriers, and any Ruby object with no counterpart in LÖVE, which arrives as the frozen copy `Ractor.make_shareable` makes. A Proc refuses, as LÖVE refuses a Lua function.
- A channel keeps its messages in C++, so a named channel's outlive every wrapper. One hidden Ruby object marks them on every collection; they are all shareable, so it may mark them for any Ractor.
- Every wait, for a message, a reader, a thread's end, or a channel another thread holds in `perform_atomic`, waits without the GVL and stays interruptible. A Ractor that waited holding it would stall the collector, which waits for every Ractor that holds its GVL.
- A thread's code that raises ends with the error's full message as its error, and Lota's loop calls `Lota.threaderror`, whose default raises it in the game, as `love.threaderror` does. Before a thread starts, Lota loads the gems Ruby decorates an error's message with on the main Ractor: Ruby 4.1.0-preview1 would otherwise fire their autoloads in the thread's Ractor, which, once `$LOAD_PATH` had changed, left the load path every Ractor shares holding that Ractor's freed objects.

Ruby still calls Ractors experimental, and warns once, as a program makes its first. A LÖVE game's threads print nothing of the kind, so Lota turns the warning off while it makes a thread's Ractor, and puts the setting back.

The sanitized build runs every Ruby thread 1:1 (`RUBY_MN_THREADS=-1`). Ruby runs another Ractor's threads M:N, on stacks it switches between without telling ASan, which then cannot clear the frames a C++ throw leaves there. The sanitizer suite runs two Ractors that write one Data and push it through one Channel while a third collects garbage, and ASan reports nothing.

## Binding cost

On a desktop a call through Rice costs about 0.4 to 0.85 µs, most of it Rice rebuilding its argument map on every call. The same draw costs about 50 ns in LÖVE. So 10,000 draws a frame take about 8 ms in Lota and 0.5 ms in LÖVE. The fixture games make 100 to 150 calls a frame, under 1% of a frame, and the heaviest, flash-blip, makes 1,300 to 2,600, 7 to 13%. `rake bench` measures it.

A phone pays more. Its CPU is slower, and Ruby runs there without a JIT, since iOS allows none and Ruby's Android build has none. The JIT matters little: on a desktop YJIT saves only 2 to 15% of a binding call. `rake bench`'s workload, run on two phones on 2026-11-09, gave:

| Call | iPhone 12 mini, iOS 27 | OnePlus Nord N30, Android 14 | LÖVE 11.5 on the Nord |
|---|---|---|---|
| `Lota::Graphics.rectangle` | 1.35 µs | 4.0 µs | 0.18 µs |
| A sprite's `draw` | not measured | 6.2 µs | 0.29 µs |
| `Lota::Graphics.width` | 0.14 µs | 0.47 µs | 0.04 µs |

The iPhone 12 mini is a near-worst case for iOS, and the Nord is a mid-range Android phone. A 60 Hz frame holds about 12,000 draws on the one and about 4,000 on the other. On the Nord a profile puts about a fifth of a call in allocating and freeing memory, which fits Rice rebuilding its argument map.

flash-blip itself was measured on the same two phones on 2026-11-12. A probe inside the game played the parity harness's script, 900 frames at a fixed 60 Hz with the same keys, and timed each frame's update and draw. In other runs it also wrapped every native call to count and time it, less the wrapper's own cost. LÖVE was 11.5, as above, with LuaJIT's compiler off, as it is on Android. Medians, with the 95th percentile in brackets:

| flash-blip, a frame | iPhone 12 mini, Lota | Nord N30, Lota | Nord N30, LÖVE 11.5 |
|---|---|---|---|
| Native calls, attract mode | 2,618 | 2,613 | 2,613 |
| Update and draw, whole run | 15.4 ms (16.3) | 10.6 ms (13.8) | 5.1 ms |
| Of that, waiting for the GPU in `setCanvas` | 9.5 ms | not measured | 0.8 ms |
| Time in native calls, attract mode | 3.5 ms | 10.1 ms | 2.3 ms |
| A native call, attract mode | 1.3 µs | 3.5 µs | 0.9 µs |

So the heaviest game Lota tests against holds 60 Hz on both phones. On the iPhone the GPU sets the pace, and the native calls, engine work included, take at most a fifth of a frame. On the Nord, Lota takes about twice LÖVE's time for the same frame, most of it Rice's cost per call, and keeps about 3 ms to spare in a slow frame. The Nord ran OpenGL ES here; on Vulkan, LÖVE 12's choice there, Lota's frame took about 10.3 ms.

Lota keeps Rice ([ADR 006](../adr/006.md)). How Lota binds the engine is no part of its public API, so a faster binding can come in any release, once games need it. The options, cheapest first:

- Remove Rice's rebuilding of its argument map on every call, in Rice or in a patch to it, which speeds up every call.
- Bind only the busiest calls, such as drawing, colors, and sound samples, through Ruby's C API directly, at a few nanoseconds a call, and keep Rice for the rest. The generator could emit them, at the cost of a second kind of binding to maintain.
- Bind everything through Ruby's C API, which also takes over what Rice does, such as turning C++ exceptions into Ruby exceptions.

A game crosses into the engine less often by drawing through a `SpriteBatch`, which takes many sprites in one call, as in LÖVE.

Neither of Ruby's JITs sees into C++. A call into a C extension is a point the JIT cannot optimize through, though it discards no compiled code. YJIT is Ruby 4.0's production JIT. ZJIT is experimental in 4.0, inlines small Ruby methods into their callers, including methods that yield, and should make the block forms of translation rules 11 and 12 cheap. As the Ruby side gets faster, binding calls become a larger share of each frame, so the benchmark runs under both JITs.

LÖVE 12 batches draws internally, so Lota binds draw calls directly. A Ruby-side batcher gets built only if the benchmark says one is needed. SpriteBatch stays the documented way to draw many sprites, as in LÖVE.
