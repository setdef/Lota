<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Performance

A game at 60 frames a second has 16.7 ms for each frame. Lota runs LÖVE's own engine, so drawing, shaders, sound, and physics cost what they cost in LÖVE. What differs is the code around them: your game runs as Ruby rather than as LuaJIT, and each call it makes into the engine crosses from Ruby into C++. This page shows what that comes to in a real game, next to the same game in LÖVE, as Lota's own benchmark, `rake bench`, measured it on one Linux computer, and what a draw call costs on an iPhone, next to the same call in LÖVE's iOS app.

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

## Draw calls on an iPhone

`rake bench:ios` runs `rake bench`'s draw-call scenarios on an iPhone or iPad connected to a Mac. A phone runs no `lota` program, so the task drives two apps that you build, sign, and install first, and launches them through Xcode's `devicectl`.

The first is Lota's bench game, as a phone project laid out and built as [the phone guide](phones.md) says, with the bench game in place of yours and `main.rb` booting it:

```sh
mkdir -p LotaBench-phone/game/bench
cp -R ~/Lota/tasks/bench/lota LotaBench-phone/game/bench/lota
cp ~/Lota/tasks/bench/recorder.rb LotaBench-phone/game/bench/recorder.rb
```

```ruby
# frozen_string_literal: true

require "lota"
exit Lota::Boot.new(File.join(__dir__, "game", "bench", "lota"), ARGV, fused: true).call
```

The second, for the comparison, is LÖVE's own iOS app, built from the LÖVE Lota pins with LÖVE's bench game in it. LÖVE's readme says to put `love-apple-dependencies`' libraries inside LÖVE's source, so build from a copy rather than change `vendor/love`. Xcode 27 builds for iOS 15 and later, and LÖVE's project asks for iOS 13, so name 15:

```sh
rsync -a --exclude .git vendor/love/ tmp/love-ios/
ln -s "$PWD/vendor/love-apple-dependencies/iOS/libraries" tmp/love-ios/platform/xcode/ios/libraries
ln -s "$PWD/vendor/love-apple-dependencies/shared" tmp/love-ios/platform/xcode/shared
xcodebuild -project tmp/love-ios/platform/xcode/love.xcodeproj -scheme love-ios -configuration Release \
  -destination generic/platform=iOS -derivedDataPath tmp/love-ios/build DEVELOPMENT_TEAM=YOURTEAMID \
  PRODUCT_BUNDLE_IDENTIFIER=com.example.LoveBench IPHONEOS_DEPLOYMENT_TARGET=15.0 -allowProvisioningUpdates build
```

LÖVE's iOS app plays the `.love` file in its own bundle as a fused game (`src/common/ios.mm`, `getLoveInResources`). Put the bench game there, sign the app again with the entitlements it was built with, and install it:

```sh
app=tmp/love-ios/build/Build/Products/Release-iphoneos/love.app
codesign -d --entitlements tmp/love-ios/entitlements.plist --xml "$app"
(cd tasks/bench/love && zip -X "$OLDPWD/$app/bench.love" main.lua conf.lua)
codesign -f -s "Apple Development" --entitlements tmp/love-ios/entitlements.plist "$app"
xcrun devicectl device install app --device DEVICE "$app"
```

Then run the task with the device's name or identifier, as `xcrun devicectl list devices` shows it, and the two apps' identifiers. Leave out `BENCH_IOS_LOVE_APP` to measure Lota alone:

```sh
BENCH_IOS_DEVICE=DEVICE BENCH_IOS_APP=com.example.LotaBench BENCH_IOS_LOVE_APP=com.example.LoveBench \
  bundle exec rake bench:ios
```

For each run of each scenario it launches the engine's app with the scenario's settings, waits until the game has written its report into its save directory, copies the report back from the app's container, and ends the app. The save directories are named for the game folder `lota` and the file `bench.love`; `BENCH_IOS_SAVE` and `BENCH_IOS_LOVE_SAVE` name others. It prints its tables and writes them to `tmp/bench/ios/report.txt`. Every scenario, three times, took 36 minutes, with the phone unlocked and its screen on throughout.

A phone measures less than a computer. iOS gives an app no memory it may write code into and run, so Ruby runs under its interpreter and LuaJIT with its JIT off. The app carries none of Lota's test-only extension, so the scenario that crosses into C++ and does nothing there does not run, and the collector's time is `GC.total_time`'s, the collecting thread's processor time, rather than the wall clock's. FLASH-BLIP does not run either: the parity harness's libraries that keep its sounds out of the speakers and the game off the network load only into a desktop process.

These numbers come from one run, on 2026-11-21, on an iPhone 12 mini with Apple's A14, iOS 27.0 (24A437), on its charger. Lota's app was built at Lota's commit `b68dbbc1`, with Fledge v0.14.0 and the prebuilt engine Lota 0.7.1 published, and the bench game as commit `532fd931` has it; LÖVE's app was built in Release from the commit Lota pins, `b7daef0f7`, with LuaJIT 2.1. Medians, of 2,000 frames of 10,000 calls each:

| Each frame's 10,000 calls | Draw loop, ms | ns a call |
| --- | --- | --- |
| A Ruby method that does nothing | 4.684 | 468 |
| `Lota::Native::Graphics.rectangle`, the binding itself | 10.009 | 1,001 |
| `Lota::Graphics.rectangle`, as a game calls it | 14.803 | 1,480 |
| LÖVE's `love.graphics.rectangle` | 6.478 | 648 |

So a rectangle takes Lota 2.29 times what it takes LÖVE on this phone. A shorter run an hour later, of 300 frames, measured 13.546 ms for Lota's rectangles and 6.417 ms for LÖVE's, so read these as a phone's rough costs, not to the tenth of a millisecond. Of Lota's 1,480 ns, Ruby's loop and method call take 468 ns, the crossing into C++ and LÖVE's own drawing 533 ns more, and Lota's Ruby layer over the binding 479 ns.

Each whole frame of these took 16.7 ms, the screen's 60 Hz, in both engines: on iOS every frame waited for the screen, though the bench games ask for no vertical sync. Where the draw loop took longer, so did the frame. Setting a color before each rectangle took Lota 22.197 ms a frame through `Lota::Native::Graphics.set_color`, and 27.200 ms through `Lota::Graphics.color=`, whose whole frames took 23.442 and 28.460 ms; it took LÖVE 5.782 ms.

One call at a time, the best of five runs of 200,000 calls, in nanoseconds:

| Call | Lota | LÖVE |
| --- | --- | --- |
| `width`, `love.graphics.getWidth` | 242 | 30 |
| `color`, `love.graphics.getColor` | 1,211 | 35 |
| `color = r, g, b, a`, `love.graphics.setColor` | 1,588 | 31 |
| `rectangle`, `love.graphics.rectangle` | 2,135 | 63 |

Reading or writing a color through `Lota::Graphics` makes an Array each call, so those scenarios made 10,007 objects a frame. Over 2,000 frames Ruby's collector ran 580 times, every time a minor collection, for 291 to 297 ms of the collecting thread's time in all and at most 0.921 ms in one frame.

## What this page does not cover

These numbers are FLASH-BLIP's, from one Linux computer with an AMD GPU, and draw calls', from one iPhone. `rake bench` has not measured macOS, Windows, or an Android phone, and no phone has played FLASH-BLIP. On a Mac the command is written to run as it is, building LÖVE's `love` with Xcode, but no Mac has run it whole yet. On Windows `rake bench` does not run. On Android, Ruby may run under YJIT, and how fast a game runs there has not been measured; `rake bench:ios` drives only iPhones and iPads.
