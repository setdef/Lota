<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Testing Against LÖVE

Lota promises that a game behaves in Lota as the same game behaves in LÖVE. Tests written beside the code cannot hold Lota to that promise, because they check Lota against what their author believes LÖVE does. So Lota checks itself against code someone else wrote: LÖVE's own test suite, Lövetest, and published LÖVE games, run in LÖVE and in Lota side by side. This page says how both work, and how the tests share your desktop while they run.

## Lövetest

`test/lovetest` holds LÖVE's own Lövetest tests (`vendor/love/testing`), translated to Ruby by the translation rules and marked as Zlib snippets. Each compares what Lota draws with LÖVE's expected image, by Lövetest's own rule. As in Lövetest, a test that asserts nothing fails with "no asserts defined" (`Lovetest::TestMethod#after_teardown`).

The tests open a real window, as Lövetest does. SDL's offscreen driver cannot create a Metal or OpenGL context on macOS, so run them in a logged-in session. On Linux they run on a display, where LÖVE draws with OpenGL, through Mesa's software renderer on CI's Xvfb, as LÖVE's Linux CI runs Lövetest.

`test/native/lota_run_test.rb` runs them all again through `lota run`, and expects as many runs as the files in `test/lovetest/tests` define test methods, so a test the game never loads is noticed.

## The parity harness

`test/parity` runs a published LÖVE game, unchanged, in a reference `love` built from `vendor/love`, and runs the game's Ruby translation in Lota. Both get a fixed `dt` and the same scripted keys and mouse, and the harness compares every frame the two show by Lövetest's rule.

The games are pinned submodules under `test/fixtures`: the arkanoid tutorial, Gravity-Wars, KleleAtoms, whose two runs must also save the same settings and game, byte for byte, and FLASH-BLIP, the heaviest, which draws every frame through four shaders and its text a rectangle a pixel, and whose two runs must save the same progress. Their translations live in `test/games`. Lota's lint, its REUSE check, and the gem all leave `test/fixtures` out, as they leave out `vendor/`. A published game joins only when its code and every asset are under licenses compatible with AGPL-3.0-or-later.

### Running it

`bundle exec rake test:parity` runs the harness, after `rake reference:love` builds the reference `love` into `tmp/reference`. On macOS that build uses LÖVE's own CI commands (`xcodebuild` archive and export, read from `vendor/love/.github/workflows/main.yml`), so it needs Xcode itself, not only its command line tools. On Linux it is the build LÖVE's Linux CI makes with love-appimage-source's Makefile, beside the libraries Lota links (`tasks/linux_build.rb`). Both compile through ccache when it is on your `PATH`. The gate runs the harness in two shards, Gravity-Wars and everything else (`PARITY_SHARDS` in `tasks/test.rake`), since Gravity-Wars alone takes as long as the rest.

When a frame differs, the harness reports the first one and the pixel where, and keeps that frame as each engine showed it in `tmp/parity-mismatches`, which CI uploads when the gate fails.

### The two sides

`test/parity/lua/conf.lua` is the harness's side in LÖVE. It mounts the game, wraps `love.update` to hold keys in SDL's keyboard state and pass the fixed `dt`, and wraps `love.draw` to save each frame with `love.graphics.captureScreenshot`. `test/parity/probe.rb` is the harness's side in Lota. It does what `conf.lua` does, loaded into `lota run` with `ruby -r`, and compares each frame with LÖVE's as it goes.

### What both sides share

A frame can match only if both engines see the same inputs, so the harness fixes every input a game reads:

- **Random numbers** come from LÖVE's own generator on both sides. The Lua side points `math.random` and `math.randomseed` at `love.math.random` and `love.math.setRandomSeed`, which `Lota::Math.random` and `random_seed=` port. Both sides fix the clock a game seeds from, `os.time()` in Lua and `Time.now` in Ruby, at the script's `clock`, fix `love.timer.getDelta` at the script's `dt` and `love.timer.getTime` at the frame's number times it, and seed the generator with the clock as the game's main file loads, for a game that draws numbers as its files load, and again before its `load`.
- **Table order** is fixed. LuaJIT seeds its string hashes at random as each Lua state starts, so `pairs` visits the same table's keys in another order each run, an order Ruby cannot reproduce. The Lua side's `pairs` visits keys in sorted order, and where a game's `pairs` loop decides what it draws or saves, as FLASH-BLIP's choice of its stars' first color does, its translation visits the keys in that order.
- **Threads** run to their end as they start. A game that waits for a thread, as FLASH-BLIP waits for the music it generates in one, would otherwise go on at whatever frame the machine finished it. The Lua side makes every `Thread:start` wait for the thread, and the Ruby side does the same for `Lota::Thread::Thread#start`. Lota has no threads yet, so FLASH-BLIP's translation runs each thread's code as it starts (`test/games/flash_blip/threads.rb`), and the test that its threads run in Lota's threads waits for them.
- **Deprecation notices** are printed until the game's `load` returns, and then turned off on both sides. LÖVE also draws them over its frames for 20 seconds of the real clock (`graphics/Deprecations.cpp`), so which frames show them changes with the machine's speed, and each engine's notices name its own files. Lota prints its notices but draws none.
- **Key presses** go into SDL's queue as key down and key up events with `SDL_PushEvent`, which LÖVE's event code turns into `keypressed` and `keyreleased`, and which need no keyboard focus.
- **The mouse** is held where the script's latest move put it with `love.mouse.setPosition`, and a click pushes SDL's button events at the pointer.
- **Dialogs**, such as LÖVE's warning that a game was made for another version, have Return pressed on them from inside the game's process. On macOS a run loop timer in AppKit's modal panel mode presses the default button. On Linux, where SDL shows a dialog through zenity or its own X11 toolkit and no code in the game can press a key on it, `liblota_dialogs` (`ext/lota/native_test/answer_dialogs_linux.cpp`) replaces `SDL_ShowMessageBox` and `SDL_ShowSimpleMessageBox` and answers as Return would, without showing the dialog. Both go through LuaJIT's FFI on the Lua side and `LotaNativeTest.press_return_on_dialogs` on the Ruby side.
- **Each run has a home of its own**, so a game that saves starts with nothing saved and leaves nothing in yours: `CFFIXED_USER_HOME` on macOS, and `XDG_DATA_HOME` on Linux (`test/test_home.rb`).
- **The environment** is the harness's own (`Parity.environment`): the system's `PATH`, the temporary folder, a UTF-8 locale, `test/alsoft.conf`, SDL's background hints, the display on Linux, and the run's own variables. Nothing from your shell reaches either engine.
- **Memory** that LÖVE reads before anything writes it is filled the same way on both sides. On Linux, Mesa's software renderer resizes a window's drawable only when it shows a frame, so a game that resizes its window in `load`, as Gravity-Wars does, captures its first frame partly from memory `malloc` gave LÖVE. Both runs set `MALLOC_PERTURB_`, so glibc fills that memory with the same byte.

### Audio

OpenAL Soft's wave file writer, which the rest of the tests play into, mixes on the wall clock, so where a sound starts in its file depends on how fast the engine ran. The harness mixes on game time instead. Both runs load `liblota_loopback` (`ext/lota/native_test/loopback.cpp`), through `DYLD_INSERT_LIBRARIES` on macOS and `LD_PRELOAD` on Linux. It replaces OpenAL Soft's `alcOpenDevice` and `alcCreateContext`, so that LÖVE's unchanged audio module gets a loopback device, 32-bit float stereo at 48 kHz, that mixes only when told to. After each `update`, each side mixes the frame's `dt` into a file of the run's own. KleleAtoms' two mixes, with its chain reaction's overlapping explosions, must then match sample for sample.

Both sides also decode the sound files a script lists with `SoundData` and `Decoder`, and must decode the same samples.

### The Metal watch

LÖVE reads a screenshot back from a buffer without asking whether the GPU ran the copy into it, and a buffer the GPU never wrote comes back as an opaque black frame. So on macOS both runs load `liblota_metal_watch` (`ext/lota/native_test/metal_watch.mm`), which draws nothing and changes nothing. It wraps `commit` and `waitUntilCompleted` on Metal's command buffers and prints, after `lota-metal-watch:`, each command buffer that ended other than completed, and at exit how many were committed, completed, failed, and waited on. The harness takes those lines out before it compares the two engines' output (`Parity.output`), and a test whose frames differ shows them in its failure (`Parity.mismatch_message`).

### The reference cache

LÖVE's side of a run does the same thing every time it gets the same inputs. So the harness keeps what it did, its frames, saved files, mixed audio, decoded sounds, printed text, and exit status, in `tmp/parity-cache` (`test/parity/reference_cache.rb`), and a later run with the same inputs reads them instead of running LÖVE again. Lota still runs, and is compared with all of it, every time.

The cache key hashes every input: the reference `love` and every file in its app, each file and folder the run names, the game's folder whether committed or not, the environment, the harness's code, and the platform, down to the system's build, the hardware, and the displays. Change any of them and LÖVE runs again. An entry whose files no longer match their recorded hashes is removed and run again, never read. The cache holds at most 512 MB, dropping the entries read least recently first. `LOTA_PARITY_CACHE=0` runs LÖVE every time and keeps nothing, as CI does.

## How tests share your desktop

Test windows stay in the background, so a test run takes no keyboard focus from what you are typing in. Every test, and every program a test starts, LÖVE's among them, gets SDL's hints `SDL_MAC_BACKGROUND_APP=1`, `SDL_WINDOW_ACTIVATE_WHEN_SHOWN=0`, and `SDL_WINDOW_ACTIVATE_WHEN_RAISED=0`. AppKit activates a program that shows a dialog regardless, so the code that presses Return on dialogs also sets the program's activation policy to prohibited. A game you run yourself gets none of this.

A few tests need more. Lövetest's `love.mouse.setGrabbed` test passes only for a window with keyboard focus, and its `love.window.isOccluded` test only for a window in front, so those two take focus while they run (`test/native/focus_for_tests.rb`). The tests that set the pointer and read it back, the cursor tests, and the parity runs that move the mouse need the pointer to themselves.

Since the gate runs its checks at once, each of those holds the desktop input lock while it runs (the `desktop_input_lock` gem), so no check takes the focus or the pointer from another. The lock, `/tmp/desktop-input.lock`, is shared with other projects that follow the same protocol. `DESKTOP_INPUT_LOCK` names another lock file, for a session whose keyboard and pointer are its own.

A test that takes the focus would also take what you type. So on a Mac, the first test to take the lock shows a notification and says aloud "Tests need the keyboard and mouse for a moment. Please step away." Once three seconds pass with no test needing them, it says you can come back. A gate may ask more than once. `DESKTOP_INPUT_QUIET`, set to anything, silences it, and CI never shows or says anything.

`LOTA_DESKTOP_UNSEEN=1` says the tests run on a Mac desktop that macOS does not draw, such as a login session kept in the background or a virtual machine without a display. SDL calls every window there occluded, so `love.window.isOccluded`'s test skips, and the gate counts the skip (`test/lovetest/unseen_desktop.rb`).

On Linux, X11 activates windows, not programs, and leaves focus to the window manager, so SDL's hints change little there. Under X11 a warp of the pointer reaches SDL only as the motion the X server sends to the window on top where the pointer lands, so a window that opens over another test's window takes that test's mouse moves. `LOTA_GATE_DISPLAYS` gives each of the gate's lanes an X display of its own, and the parity harness uses its lane's (`LOTA_PARITY_DISPLAY`, `Parity.display`). SDL also answers a clipboard request from a window that is gone without guarding against it, which Xlib's default error handler would turn into the end of the run, so the test extension lets that one error pass (`ext/lota/native_test/selections_linux.cpp`).
