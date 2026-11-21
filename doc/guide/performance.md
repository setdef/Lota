<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Performance

A game at 60 frames a second has 16.7 ms for each frame. Lota runs LÖVE's own engine, so drawing, shaders, sound, and physics cost what they cost in LÖVE. What differs is the code around them: your game runs as Ruby rather than as LuaJIT, and each call it makes into the engine crosses from Ruby into C++. This page shows what that comes to in a real game, next to the same game in LÖVE, as Lota's own benchmark, `rake bench`, measured it on one Linux computer.

## The game, the computer, and the command

The game is [FLASH-BLIP](https://github.com/plinkr/flash-blip), a published LÖVE game and the heaviest of the four that Lota's CI plays in both engines and compares frame by frame. Every frame it draws through four shaders, a glow, a blur, scanlines, and a CRT's curve, and it draws its text one rectangle a pixel. LÖVE plays the game unchanged, and Lota plays [its Ruby translation](../../test/games/flash_blip).

Both engines play the same 900 frames: the game plays itself under its menu, Return starts a game at frame 300, and the space bar blips every 40 frames from frame 400 until an obstacle ends the game. Both get the same fixed time step, the same clock, and the same keys, through the harness Lota's parity tests use ([Testing against LÖVE](../contributors/parity.md)), which here takes no screenshots and times every frame instead. Lota plays the script three ways: under Ruby's interpreter, under YJIT, and under ZJIT. Each way plays it three times, and `rake bench` keeps the run with the shortest median update and draw, since anything else on the computer only adds time.

The numbers on this page come from one run, on 2026-11-21, on this computer, with nothing else running on it:

| | |
| --- | --- |
| Processor | AMD Ryzen AI 9 HX 370, 24 processors, 91 GB of memory |
| GPU | AMD Radeon 890M, through Vulkan 1.4.335 (Mesa's RADV driver) |
| System | Ubuntu 26.04.1 LTS, Linux 7.0.0 |
| Ruby | 4.1.0-preview1, compiled with YJIT and ZJIT |
| LÖVE | the commit Lota pins, `b7daef0f7`, with LuaJIT 2.1 |
| Lota | commit `c7bfa39b5` |

The command, run in a clone of Lota after `bin/setup`:

```sh
BENCH_SCENARIOS=flash_blip,flash_blip_native_calls bundle exec rake bench
```

It builds Lota, and LÖVE's own `love` from the commit Lota pins, plays the game 21 times, prints its tables, and writes them to `tmp/bench/report.txt`. Run it on your computer to see your own numbers, and run it more than once: the smallest numbers on this page, such as Ruby's share of a frame, move from one run to the next. On a Linux computer with no desktop it opens its windows on displays of its own, and `LOTA_GATE_GPU=vulkan` puts them on the GPU, as it did here ([Developing Lota](../contributors/development.md#on-a-computer-with-no-desktop)).

## A frame of FLASH-BLIP

*Update and draw* is the time the game's own `update` and `draw` took together: the work your code decides, with every call it makes into the engine. *Frame* is the whole frame, from the start of one `update` to the start of the next, which adds the engine's own work: handling events, clearing, presenting the frame to the GPU, and the loop's 1 ms sleep. The game's window asks for vertical sync, but this display showed its frames as fast as they came, so neither column waits for the screen. Times are in milliseconds, as the median, the 99th percentile, and the slowest of the 900 frames.

| Engine | Update and draw | Times LÖVE's median | Frame |
| --- | --- | --- | --- |
| Lota, interpreter | 2.099 / 3.933 / 11.596 | 14.84 | 3.238 / 5.235 / 13.286 |
| Lota, YJIT | 1.684 / 5.328 / 16.755 | 11.90 | 2.828 / 6.749 / 17.927 |
| Lota, ZJIT | 1.748 / 5.141 / 23.717 | 12.36 | 2.907 / 6.883 / 24.998 |
| LÖVE | 0.141 / 0.455 / 6.468 | 1.00 | 2.034 / 2.157 / 7.613 |

The game's own work takes 11.90 to 14.84 times as long in Lota as in LÖVE: 1.684 to 2.099 ms against 0.141 ms. The whole frame differs far less, 2.828 to 3.238 ms against 2.034 ms, since the engine's own part of it is the same in both. Either way the median frame leaves most of a 60 Hz frame's 16.7 ms free. The slowest Lota frame under the interpreter, 13.286 ms, still fits; under YJIT one frame took 17.927 ms, and under ZJIT one took 24.998 ms, which the section on YJIT and ZJIT explains.

## How much of it is Ruby

A second run under each way of running Ruby wraps every method of Lota's extension, and times each call the game's `update` and `draw` make into it, less what the wrapper itself adds. Those calls take in both the crossing from Ruby into C++ and LÖVE's own work. What is left of the update and draw is Ruby: the game's code and Lota's Ruby layer. Medians, in milliseconds:

| Ruby | Calls into the engine a frame | Update and draw | In the engine's calls | In Ruby | Ruby's share of the frame |
| --- | --- | --- | --- | --- | --- |
| Interpreter | 1,707 | 2.099 | 1.928 | 0.172 | 5.3% |
| YJIT | 1,707 | 1.684 | 1.633 | 0.051 | 1.8% |
| ZJIT | 1,707 | 1.748 | 1.974 | -0.226 | -7.8% |

The update and draw come from the run without wrappers, and the calls from the run with them, so Ruby's part is the difference of two runs' medians. It is small enough that two runs can disagree on it, and under ZJIT they did: the calls in the wrapped run took longer than the whole update and draw of the run without wrappers, so the difference came out below zero. Read ZJIT's row as saying only that its Ruby is too small for this method to measure.

So in a game like this one, Ruby is not where the time goes. The calls into the engine are: FLASH-BLIP makes 1,707 of them a frame, which take Lota 1.633 to 1.974 ms, while LÖVE runs the same calls, and all of the game's Lua besides, in 0.141 ms. A game that draws many sprites crosses into the engine fewer times by drawing them through a `SpriteBatch`, as in LÖVE.

## What YJIT and ZJIT buy

YJIT takes the median update and draw from 2.099 ms to 1.684 ms, and ZJIT to 1.748 ms. YJIT cuts Ruby's own part, from 0.172 ms under the interpreter to 0.051 ms. Ruby's own part is small in this game, so neither changes the whole frame much: its median goes from 3.238 ms to 2.828 ms under YJIT and 2.907 ms under ZJIT. And both make the slow frames slower: the 99th percentile of the update and draw is 3.933 ms under the interpreter, 5.328 ms under YJIT, and 5.141 ms under ZJIT.

YJIT compiles a method only once it has been called 30 times (`--yjit-call-threshold` in Ruby's [YJIT documentation](https://github.com/ruby/ruby/blob/master/doc/jit/yjit.md)), and compiling takes time of its own, so the first run of a large code path is slower under a JIT than under the interpreter. Here the slowest update and draw under YJIT took 16.755 ms, in frame 146, while the game played itself under its menu; under ZJIT it took 23.717 ms, in frame 400, where the first blip comes; and under the interpreter 11.596 ms, in frame 697.

The `lota` program runs your game under the Ruby you start it with, so `RUBY_YJIT_ENABLE=1 lota path/to/game` turns YJIT on while you work. A game that `lota fuse` builds turns YJIT on wherever its Ruby has it ([Sharing a game](sharing.md#restarting-and-what-is-missing)). RubyInstaller's Ruby, which Lota's Windows gems are built for, has no YJIT, so on Windows a game runs under the interpreter, from `lota` and as an app.

## Pauses for garbage collection

Lota's game made 2,481 Ruby objects a frame under each way of running Ruby. Over the 900 frames, Ruby's collector ran 46 to 64 times, two of them full (major) collections, both of which Ruby started because it had run out of free slots (`nofree`). In milliseconds:

| Ruby | Collections (minor / major) | Collecting, in all | Most collecting in one frame |
| --- | --- | --- | --- |
| Interpreter | 57 (55 / 2) | 48.428 | 10.951 |
| YJIT | 46 (44 / 2) | 52.660 | 4.968 |
| ZJIT | 64 (62 / 2) | 55.755 | 10.919 |

That is little over the whole run, but one frame under the interpreter paused for 10.951 ms, and one under ZJIT for 10.919 ms, most of a 60 Hz frame. LÖVE's Lua has a collector of its own, which `rake bench` does not time.

`rake bench` times each collection by the wall clock, from the moment Ruby's collector starts a step to the moment it ends it. It does not use `GC.total_time`, which adds up the collecting thread's CPU time, or on Windows the process's, which Windows advances only at its clock's tick, every 15.6 ms by default, so a collection shorter than a tick mostly reads as none there (Ruby's `gc/default/default.c`, `current_thread_time` and `current_process_time`). If you time your own game's collections on Windows, time them by the wall clock too.

## What this page does not cover

These numbers are this game's, from one Linux computer with an AMD GPU. `rake bench` has not measured macOS, Windows, or a phone. On a Mac the command is written to run as it is, building LÖVE's `love` with Xcode, but no Mac has run it whole yet. On Windows `rake bench` does not run. A phone's processor is slower than a desktop's, and on an iPhone or iPad Ruby runs with no JIT at all, since iOS gives an app no memory it may write code into and run.
