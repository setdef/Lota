<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Developing Lota

This page is for people who build Lota from source, change it, or run its checks. To make a game with Lota, start with the [README](../../README.md). [AGENTS.md](../../AGENTS.md) holds the project's rules, [ADR 001](adr/001.md) records what Lota is and why, and [releasing.md](releasing.md) says how a release is cut.

## Getting the source

Clone with submodules. `vendor/love` holds the LÖVE source Lota builds against, `vendor/love-apple-dependencies` holds the prebuilt libraries LÖVE links on macOS (SDL3, FreeType, HarfBuzz, OpenAL Soft, and the rest), and `vendor/love-appimage-source` holds the Makefile LÖVE's own Linux CI builds those libraries from source with.

```bash
git clone --recurse-submodules https://github.com/setdef/lota.git
bin/setup
bundle exec rake
```

`bin/setup` installs the pinned tools from `mise.toml`, CMake, Ninja, clang-format, and clang-tidy among them, and on Linux patchelf. It also runs `bundle exec rake sources:fetch`, which downloads the source archive of each framework or library whose license asks the gem to carry its source, so far OpenAL Soft's 1.24.3 release (about 1 MB), into `vendor/sources`, which git ignores, and keeps it only when its SHA-256 is the one `ext/lota/licenses.rb` records; on Linux it also runs the Makefile's downloads, the release of each library it builds, into `vendor/sources/linux`. The gate never downloads anything.

On Linux, first install the packages LÖVE's own Linux CI installs to build its dependencies (the `apt-get install` in `.github/workflows/ci.yml`'s Linux gate, for Ubuntu 22.04 or newer), and run the tests on a display: the CI runs them on Xvfb with Openbox, as LÖVE's runs Lövetest.

### Ruby and ZJIT

mise compiles Ruby from source with ruby-build, which needs its [suggested build environment](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment), because mise's precompiled Ruby for macOS, from `jdx/ruby`, is built without ZJIT, and `rake bench` measures ZJIT. Ruby builds ZJIT only with Rust 1.85 or newer, so mise first installs the Rust that `mise.toml` pins and compiles Ruby with it; an install that finds no Rust fails rather than leave ZJIT out. Compiling takes about three minutes, once. mise does not compile a Ruby of the pinned version it installed before; `mise install --force ruby` replaces it, and `ruby --zjit -e 'p RubyVM::ZJIT.enabled?'` prints `true` from a Ruby that has ZJIT.

## The gate

`bundle exec rake` is the gate. It builds LÖVE's engine and the `Lota::Native` extension into `tmp/engine/build`, on Linux after `rake dependencies` has built LÖVE's dependencies into `tmp/dependencies` with love-appimage-source's Makefile, from what `sources:fetch` downloaded, as LÖVE's Linux CI builds them (`tasks/linux_build.rb`). It runs the tests (the native ones a second time under AddressSanitizer and UndefinedBehaviorSanitizer), then runs the C++ gates over Lota's own C++ in `ext/`.

Those checks, with the lint, type, package, and parity checks, run at the same time in lanes (`tasks/gate.rake`): `bundle exec rake` first fixes what RuboCop can and builds, then runs each check in a rake process of its own, holds each one's output until it ends, prints it whole in a fixed order with the failing check marked and the gate's exit status nonzero, and ends with a table of how long each took. `LOTA_GATE_JOBS=1` runs the same checks one after another.

What it holds says nothing while a check runs, so the gate also prints, as it happens and stamped with the time of day, a line as each check starts and ends, and every `LOTA_GATE_HEARTBEAT` seconds (120 unless set) a line naming each check still running, its lane, and how long it has run. Every lane must end within `LOTA_GATE_LANE_TIMEOUT` seconds of the gate's start, prepare steps included, since that is where a CI step's limit counts from; the gate prints the budget as it starts. A check still running then, or whose process has exited while a process it started still holds its output open, is timed out: the gate prints what it has printed so far, the tree of its processes from `ps` (its descendants and anything left in its process group), and a stack of each, from `/usr/bin/sample` on macOS and `eu-stack` or `gdb` on Linux where either is installed, then sends TERM to the check's process group, which it started the check in, and KILL ten seconds later to whatever is left. The check is marked `TIMED OUT` in the report, its lane starts no more checks, and the gate fails. The budget is three hours unless set, about five times the slowest healthy lane CI has run and past the slowest run of every check one after another, so that it ends only a check that is hung. CI's macOS gate sets 2280 seconds, two minutes inside GitHub's 40-minute limit on its step, and its Linux gate 5880, two minutes inside its 100: a gate past those would be ended by GitHub without a word, and healthy macOS gates have taken up to about 36 minutes.

On Linux, `LOTA_GATE_DISPLAYS` lists, separated by spaces, an X display for each lane in `tasks/gate.rake`'s order, on which that lane's checks open their windows: under X11 a warp of the pointer reaches SDL only as the motion the X server sends to the window on top where the pointer lands, so a window of one lane's tests that opens over another's takes the moves Lövetest's mouse tests make, and they read back where the pointer was before. CI's Linux gate starts a display of Xvfb's, with Openbox, for each lane but the last, whose checks open no window; without the variable every lane shares `DISPLAY`.

A clean run takes about seven minutes, most of it compiling the engine twice and building the reference `love` the parity harness compares Lota with, and a run with nothing to rebuild about two, most of it the parity harness running Lota beside the test shards.

## Rake tasks for the native side

- `bundle exec rake compile` builds the engine and the extensions and copies `Lota::Native` to `lib/lota/native.bundle`. rake-compiler runs `ext/lota/extconf.rb`, which configures the CMake project in `ext/lota` and writes a Makefile that builds it. The source gem's `gem install` runs the same script, which stops there, since the gem ships no LÖVE sources, and names the precompiled gem. CMake decides what to rebuild, so `rake compile` always calls it, and a build with no changes takes a second or two.
- `bundle exec rake engine:sources` regenerates the list of LÖVE sources the engine compiles on the platform it runs on, `ext/lota/engine/sources_macos.cmake` or `sources_linux.cmake`, after a bump of `vendor/love`. `rake engine:sources:check` fails until you do, so review the difference before you commit it; each platform's list is checked on that platform.
- `bundle exec rake bindings:generate` writes the bindings `ext/lota/bindings.rb` lists (see [Bindings](#bindings)).
- `bundle exec rake package:native`, `package:check`, `package:install`, and `package:deliver` build and check the precompiled gem (see [Packaging](#packaging)).
- `bundle exec rake cpp` runs `cpp:format`, `cpp:no_nolint`, and `cpp:tidy`; `rake cpp:format:fix` rewrites the layout clang-format reports. `cpp:tidy` starts a clang-tidy for each source, as many at once as the machine has cores, as LLVM's `run-clang-tidy` does, since each of Lota's sources parses Rice's headers, which one clang-tidy for all of them did one after another.
- `bundle exec rake lint:workflows` checks `.github/workflows` with actionlint, and each step's script with shellcheck. Both are pinned in `mise.toml`, and the task fails without shellcheck, which actionlint would skip without a word.

## Sanitizers

`bundle exec rake test:native` rebuilds everything with ASan and UBSan into `tmp/sanitize/build` and runs `test/native`, `test/lovetest`, and `test/sanitizers` against it. ASan has to be in the Ruby process before anything it instruments, so the task starts Ruby directly with `DYLD_INSERT_LIBRARIES`; a shell or a binstub in between would drop it, because macOS removes `DYLD_` variables when it starts a protected binary such as `/bin/sh`.

On Linux the sanitizers are GCC's, which builds LÖVE's Linux engine, loaded with `LD_PRELOAD` together with the C++ runtime, which ASan's interceptor of C++ exceptions must find when it starts, before Ruby, which is C, loads it for an extension, and with LeakSanitizer off, as macOS's ASan runs without it.

`test/sanitizers` holds deliberate memory bugs, and only this task runs it.

## The patches

LÖVE's physics module holds Lua in its engine classes, so Lota changes it with a patch, `ext/lota/engine/physics.patch` (ADR 001, section 2): when CMake configures the engine it copies `vendor/love/src/modules/physics` into the build tree's `patched/love`, applies the patch with `patch`, and compiles the copy, whose headers come before LÖVE's own, so `vendor/love` is never written to. A file the patch no longer applies to stops the configure. The patched files keep LÖVE's code, and replace each read or push of the Lua stack with C++ parameters and results, and each Lua reference with the `Reference` interfaces in the patch's new `Reference.h`, which `ext/lota/native/physics.cpp` implements. To change it, apply it to a copy of the module, edit the copy, and write the patch again with `diff -ruN`, paths starting `a/src` and `b/src`.

The other patch, `ext/lota/engine/mesh.patch`, changes one statement of `src/modules/graphics/Mesh.cpp`, so that a Mesh frees its vertex data with `delete[]`, as it allocated it, where LÖVE's frees it with `delete`, which AddressSanitizer on Linux reports when the first Mesh is destroyed (`doc/contributors/upstream/005.md`). CMake applies it as it does the physics patch, to a copy of the file in `patched/love`, which it compiles with `-iquote` naming the file's own folder in `vendor/love`, so that the headers it includes in quotes are found where they were.

## Bindings

`bundle exec rake bindings:generate` writes the bindings `ext/lota/bindings.rb` lists from LÖVE's `wrap_*.cpp` files, by ADR 001's rules and the names `binding_exceptions.rb` records, into `ext/lota/native/generated` and `sig/lota/native/generated.rbs` (`tasks/bindings`), and the Ruby name the rules give every function of LÖVE's API into `lib/lota/error_message/names.rb`, a frozen Hash that every Ractor can read, which `Lota::ErrorMessage` translates the engine's error messages with as Ruby raises them. Those files are never edited by hand. Where LÖVE replaces a wrap function's C++ with LuaJIT code of its own, in a `wrap_*.lua` file, the generator knows it, refuses to port the C++, and `bindings.rb` lists the function with `bound_from_lua`, for Lota's hand-written port of the Lua.

`rake bindings:check` fails, before the engine builds, until the committed files match what the generator writes. `rake "bindings:report[tmp/report.txt]"` lists every LÖVE function that fits no rule, fits several, or leaves a rule's decision open, and every function the parser cannot read, each with its file, line, and why.

Bindings live in `ext/lota/native`. Each one includes `native/binding.hpp`, never Rice's own header, because `binding.hpp` is where every `love::Object` gets LÖVE's memory model (ADR 001, section 5): a Ruby wrapper holds one reference from the moment Ruby wraps the object until the garbage collector frees the wrapper. `ext/lota/native_test` is a test-only extension, `LotaNativeTest`, that the tests load from the build tree; the gem never packages it. `Lota::Native` has no RBS generator yet, so its signatures in `sig/lota/native.rbs` are written by hand, and `rbs:parity` checks them against the compiled extension.

### The main thread

Graphics and window calls run only on the process's main thread, as LÖVE keeps `love.graphics` and `love.window` there, and raise `ThreadError` anywhere else. Ruby's garbage collector can free a wrapper on any thread, so a wrapper of a graphics or window object freed off the main thread hands its reference to a release queue, which the main thread drains with `Lota::Native.drain_release_queue` (and at exit). Every class bound from those two modules belongs in `ReleasedOnMainThread` in `binding.hpp`.

## Packaging

`bundle exec rake package:native` builds the precompiled gem for the platform it runs on, `pkg/lota-<version>-arm64-darwin.gem`, or on Linux `x86_64-linux-gnu` or `aarch64-linux-gnu`, from `rake compile`'s bundle (`tasks/native_gem.rb`).

On Linux it carries the shared libraries the bundle needs, and those they need, in `lib/lota/libraries`, each under the soname it is needed by, without its debugging information, its rpath pointed by patchelf at that folder (`$ORIGIN`) as the bundle's is, as LÖVE's AppImage carries them, relying on the system for glibc and GCC's C++ runtime alone (`tasks/native_format.rb`); its platform names glibc, so RubyGems does not pick it on musl.

What follows describes the macOS gem; the Linux gem's record is the same in its own terms. It carries the bundle, the frameworks it loads (SDL3, FreeType, HarfBuzz, OpenAL Soft, libmodplug, libvorbis, and the libogg libvorbis loads, arm64 only and without headers) in `lib/lota/frameworks`, and a record of who wrote them under which licenses, by the REUSE Specification as the repository is: its `REUSE.toml` is the repository's with an annotation for the bundle and one for each framework, written from `ext/lota/licenses.rb`, and its `LICENSES` holds the text of every license its files use, the ones only the gem uses coming from `ext/lota/licenses`. The bundle's annotation names the libraries the linker put in it, which the build reads from the linker's map (`lib/lota/native.map` in the build tree) and ninja's dependency log. The bundle's rpaths, which point into `vendor/`, are replaced by `@loader_path/frameworks`, and the bundle and every framework are signed again ad hoc and verified with `codesign --verify --strict`. A framework, or a file the bundle was compiled from, that `ext/lota/licenses.rb` does not record stops the build, and so does a gem `reuse lint` does not call compliant.

OpenAL Soft is a framework of its own, which the bundle links as LÖVE's macOS build does, so a player can replace it, and its license, the GNU Library General Public License, asks for its source with every copy of its object code, so the gem carries the release's source archive in `sources/`, with an annotation of its own in `REUSE.toml` naming every license and notice in it; the build copies it from `vendor/sources` after checking its SHA-256, and stops without it.

`bundle exec rake package:check` checks that the source gem's `gem install` stops with that message, then runs `reuse lint` on the precompiled gem's unpacked package, checks that each framework whose record names a source archive is in it with its annotation and the archive, the one recorded, and loads the gem from it.

`rake package:install` builds the precompiled gem as `package:native` does, then delivers it as `rake "package:deliver[path/to/lota-<version>-arm64-darwin.gem]"` delivers a gem built elsewhere: it installs the gem into an empty `GEM_HOME` that sees no other gem, runs `lota --version`, and runs `lota run` on two games: one that opens a window and quits with a status of its own, and `test/lovetest/game`, which runs the translated Lövetest tests against LÖVE's expected images, with Minitest installed beside the gem. Each run plays its sounds through OpenAL Soft's null backend (`ALSOFT_DRIVERS=null`), so it needs no audio device, and must end with its expected status and output, load Lota, its bundle, and SDL3 only from the installed gem, and load nothing from the repository's `lib/`, which a guard loaded into the run checks. dyld reports what a run loads on macOS; on Linux the guard reports what the run mapped (`/proc/self/maps`), and every library that is neither the system's nor Ruby's must be the installed gem's. `package:deliver` builds nothing, so it runs where the gem was never built. Both checks fail on any warning `gem build` prints. They take seconds, and `bundle exec rake` runs `package:check` and `package:install`.

## Continuous integration

GitHub Actions runs `.github/workflows/ci.yml` on every push and pull request, on GitHub's Apple Silicon runners with macOS 15 (`macos-15`), whose session is logged in, so the tests open real windows there as on your Mac, and beside them on Ubuntu 22.04 runners for x86_64 and arm64 (`ubuntu-22.04`, `ubuntu-22.04-arm`), whose Linux gate and delivery jobs do on Linux what the macOS ones do, on a display of Xvfb's with Openbox, as LÖVE's own Linux CI runs Lövetest, and cache the libraries `rake dependencies` builds.

The **Gate** job installs the Ruby that `mise.toml` pins with `ruby/setup-ruby` and the other tools in `mise.toml` with mise, runs `bundle exec rake`, fails if the gate changed a file (its `lint:fix` step corrects what it can, which would otherwise pass unnoticed), and builds the precompiled gem with `rake package:native` as an artifact. Compiled objects come from ccache, which reuses one only when the compiler, its arguments, and every file it reads are the same.

The **Delivery** job then downloads that gem on a fresh runner that builds nothing and fetches only `vendor/love`, for LÖVE's expected images, installs the same Ruby, and runs `rake package:deliver` on it, so the walking skeleton's acceptance test, Lövetest's `love.test.graphics.clear`, passes from the installed gem.

CI's Ruby comes from `ruby/setup-ruby` rather than mise, and mise skips both Ruby and the Rust it pins for compiling Ruby, because setup-ruby's Ruby is already built by ruby-build with Rust, as the Ruby mise compiles is, so it has ZJIT without compiling Ruby on every run.

### Windows

The gate does not run on Windows: GitHub's Windows runners have no GPU, and Windows' own OpenGL is 1.1, which LÖVE's renderer cannot use, so nothing there opens a window. The **Windows build** job builds LÖVE's dependencies from source at LÖVE's versions (`tasks/windows_build.rb`), with GCC from MSYS2's UCRT64 environment on x64 and clang from its CLANGARM64 environment on ARM64, the toolchains RubyInstaller builds its Ruby with. It checks `ext/lota/engine/sources_windows.cmake` against `vendor/love`, configures through `ext/lota/extconf.rb`, builds the engine and the extension, checks that Lota's code still warns as errors, checks the extension's closure of DLLs and that each loads from the gem's own directory even with a decoy `OpenAL32.dll` on the `PATH`, restarts a game, runs the tests that open no window and need no test-only extension, and builds the gem with `ruby .github/windows_checks.rb package`. The **Windows delivery** job installs that gem on a runner without MSYS2, with a `PATH` of only Ruby, Windows, PowerShell, and Git, and runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`.

A tag runs all of these jobs again, and the release job publishes the gems only when every platform passed ([releasing.md](releasing.md)).

## The parity harness

`test/parity` is the parity harness (Plan 001): it runs a published LÖVE game, unchanged, in a reference `love` built from `vendor/love`, and the game's Ruby translation in Lota, both with a fixed `dt` and the same scripted keys, and compares every frame the two show by Lövetest's rule. The games are pinned submodules under `test/fixtures` (the arkanoid tutorial, Gravity-Wars, and KleleAtoms, whose two runs must also save the same settings and game, byte for byte), which Lota's lint and REUSE checks and the gem leave out, as they leave out `vendor/`; their translations live in `test/games`.

`test/parity/lua/conf.lua` is the harness's side in LÖVE: it mounts the game, wraps `love.update` to hold keys in SDL's keyboard state and pass the fixed `dt`, and wraps `love.draw` to save each frame with `love.graphics.captureScreenshot`. `test/parity/probe.rb` is the harness's side in Lota, which does what `conf.lua` does, loaded with `ruby -r` into `lota run`, and compares each frame with LÖVE's as it goes, reporting the first that differs and the pixel where, and keeping that frame, as each engine showed it, in `tmp/parity-mismatches`, which CI uploads when the gate fails.

### Running it

`bundle exec rake test:parity` runs it, after `rake reference:love` builds the reference into `tmp/reference` with LÖVE's own macOS CI commands (`xcodebuild` archive and export, read from `vendor/love/.github/workflows/main.yml`), compiling through ccache when it is on the `PATH`. That build needs Xcode itself, not only its command line tools. A clean build takes about two minutes, a build from ccache about 25 seconds, and a build of the same commits nothing. `bundle exec rake` runs both.

### Inputs both sides share

Random numbers come from LÖVE's own generator on both sides, as Plan 001 has them: the Lua side points `math.random` and `math.randomseed` at `love.math.random` and `love.math.setRandomSeed`, which `Lota::Math.random` and `random_seed=` port, and both sides fix the clock a game seeds from, `os.time()` in Lua and `Time.now` in Ruby, at the script's `clock`, so a game that seeds from the time draws the same numbers in both. Both sides also fix `love.timer.getDelta` at the script's `dt` and seed LÖVE's generator with the script's clock before the game's `load`.

Where a game needs a key press rather than a held key, as on Escape to quit, the script presses it: both sides also push SDL's key down and key up events into SDL's queue with `SDL_PushEvent`, which LÖVE's own event code turns into `keypressed` and `keyreleased`, and which, unlike a key macOS reports, does not need the window to have keyboard focus.

A dialog either engine shows, such as LÖVE's warning that a game was made for another version, has Return pressed on it from inside the game's own process: a run loop timer in AppKit's modal panel mode, which runs only while a dialog is up, presses the dialog's default button, the one Return presses, through LuaJIT's FFI on the Lua side and `LotaNativeTest.press_return_on_dialogs` on the Ruby side, so it needs neither keyboard focus nor Accessibility permission.

The mouse moves and clicks as the script says, on both sides: the pointer is held where the script's latest move put it with `love.mouse.setPosition`, which updates SDL's mouse state and queues `mousemoved`, and a click pushes SDL's button events at the pointer's position, which LÖVE turns into `mousepressed` and `mousereleased`.

Each run, LÖVE's and Lota's, has a home directory of its own (`CFFIXED_USER_HOME`), so a game that saves, as KleleAtoms saves its settings and a game, starts with nothing saved and leaves nothing in yours, and the runs make no sound and play the same with or without an audio device.

### Audio

OpenAL Soft's wave file writer, which the rest of the tests play into (`test/alsoft.conf`, as LÖVE's CI plays Lövetest's sounds), mixes on the wall clock, in steps of 20 milliseconds, so where a sound starts in its file depends on how fast the engine ran. So both runs load `liblota_loopback` (`ext/lota/native_test/loopback.cpp`, built beside the test extension) with `DYLD_INSERT_LIBRARIES`, which interposes OpenAL Soft's `alcOpenDevice` and `alcCreateContext` so that LÖVE's unchanged audio module gets a loopback device (`ALC_SOFT_loopback`), 32-bit float stereo at 48 kHz, OpenAL Soft's defaults, which mixes only when told to; after the game's `update`, each side tells it to mix the frame's `dt`, through LuaJIT's FFI in LÖVE and `LotaNativeTest.render_loopback` in Lota, into a file of the run's own. Mixing is then on game time, and KleleAtoms' two mixes, its chain reaction's overlapping explosions among them, must match sample for sample. Both sides also decode the sound files a script lists, KleleAtoms' and Lövetest's, with `SoundData` and `Decoder` when the game loads, and must decode the same samples, byte for byte. The test suite does the same for every test and every program a test starts (`test/test_helper.rb`), but for the loopback device.

### The Metal watch

On macOS both runs also load `liblota_metal_watch` (`ext/lota/native_test/metal_watch.mm`, built beside the test extension), which draws nothing and changes nothing either engine does. LÖVE copies a frame it takes a screenshot of into a buffer, waits for the GPU, and reads the buffer back without asking whether the GPU ran the copy, and a buffer the GPU never wrote comes back as an opaque black frame. The watch interposes Metal's `MTLCreateSystemDefaultDevice` and `MTLCopyAllDevices`, and on the class of command buffer each device makes it wraps `commit` and `waitUntilCompleted`, so it prints, after the prefix `lota-metal-watch:`, each command buffer that ended other than completed, with its status and error, and at exit how many were committed, completed, failed, and waited on. The harness takes those lines out of what each engine printed before comparing the two (`Parity.output`), and a test whose frames differ shows them, with the last lines each engine printed, in its failure (`Parity.mismatch_message`).

### Windows in the background, and focus

Test windows stay in the background, so a test run takes no keyboard focus from what you are typing in: every test, and every program a test or `rake package:install` starts, LÖVE's among them, gets SDL's hints `SDL_MAC_BACKGROUND_APP=1`, `SDL_WINDOW_ACTIVATE_WHEN_SHOWN=0`, and `SDL_WINDOW_ACTIVATE_WHEN_RAISED=0`, and since AppKit activates a program that shows a dialog regardless, the code that presses Return on dialogs, on both sides, also sets the program's activation policy to prohibited, which keeps it from ever being activated while it still shows its windows and dialogs. A game you run gets none of this.

Lövetest's `love.mouse.setGrabbed` test passes only for a window with keyboard focus, and its `love.window.isOccluded` test only for a window in front of the others, so those two alone take focus, for the moment each runs (`test/native/focus_for_tests.rb`), and `package:install` runs `test/lovetest/game` in the foreground.

### The desktop input lock

Because the gate's checks run at the same time, both hold the desktop input lock while they have the focus (the `desktop_input_lock` gem), as do the tests that set the pointer and read it back, Lövetest's other mouse tests, the cursor tests, and the parity runs that move the mouse, so no check takes the focus or the pointer from another. The lock, `/tmp/desktop-input.lock`, is shared with other projects that follow the same protocol, so their tests and Lota's wait for each other too. The `DESKTOP_INPUT_LOCK` variable names another lock file, for a session whose keyboard and pointer are its own.

`LOTA_DESKTOP_UNSEEN=1` says the tests run on a desktop that macOS does not draw, such as a login session kept in the background or a virtual machine without a display: macOS counts no window there as seen, and SDL calls a window occluded once macOS has said so, so `love.window.isOccluded`'s test skips there, the one test that changes, and the gate counts that skip (`test/lovetest/unseen_desktop.rb`). It is off unless set, and means nothing on Linux.

A test that takes the focus would also take what you type, so on a Mac, the first to take the lock shows a Notification Center banner, which takes no focus, and then says aloud, with macOS's `say`, "Tests need the keyboard and mouse for a moment. Please step away.", and leaves `/tmp/desktop-input.away` to say it did, so that the gate's other processes, and other projects', do not say it again; once three seconds pass with no test needing them and no one holding the lock, a process shows and says "The tests are done with the keyboard and mouse. You can come back now." and removes the file. A Mac without `say`, or with its sound off, still shows the banners. The checks that take the focus run in different lanes, at times their tests' random order picks, so a gate may ask more than once, each time for only as long as they hold the lock; the tests that only set the pointer, whose windows stay in the background, hold the lock without a word. Nothing is shown or said on CI or under `DESKTOP_INPUT_QUIET`, set to anything.

### The reference cache

LÖVE's side of a run does the same thing every time it gets the same inputs, so the harness keeps what it did, its frames, saved files, mixed audio, decoded sounds, printed text, and exit status, in `tmp/parity-cache` (`test/parity/reference_cache.rb`), and gives a later run under the same inputs that instead of running LÖVE again; Lota still runs, and is compared with all of it, every time.

Both engines start with an environment of the harness's own (`Parity.environment`): the system's `PATH`, the temporary folder, a UTF-8 locale, `test/alsoft.conf`, SDL's background hints, on Linux the display, and the run's own variables, and none of your shell's, so nothing of a terminal session's changes what either engine does. The key is the hash of every input the run has: the reference `love` and every file in its app bundle, each file and folder its arguments and environment name, the game's folder whether committed or not, that whole environment, the harness's code, and the platform, down to the system's build, the hardware, and the displays. Anything that changes one of them runs LÖVE again, and an entry whose files do not match the hashes it recorded is removed and run again, never read.

A cold run of the harness takes about three and a half minutes and a warm one about a minute and a half; the cache holds at most 512 MB, the entries read least recently going first, and one set of runs takes about 190 MB. `LOTA_PARITY_CACHE=0` runs LÖVE every time and keeps nothing, as CI does.

### On Linux

On Linux the harness does the same in Linux's terms. The reference `love` is the one LÖVE's own Linux CI builds, with love-appimage-source's Makefile, beside the dependencies Lota links (`rake reference:love`, `tasks/linux_build.rb`), and runs from its installdir, as the AppImage's own launcher runs it. A run's home is given to LÖVE's filesystem through `XDG_DATA_HOME`, under which it saves on Linux, so LÖVE saves in the run's `.local/share/love` and Lota in its `.local/share/lota` (`test/test_home.rb`). `liblota_loopback` goes in with `LD_PRELOAD`, whose own `alcOpenDevice` and `alcCreateContext` then come before OpenAL Soft's.

Mesa's software renderer gives a window's OpenGL drawable a new size only when it shows a frame, so a game that resizes its window in `load`, as Gravity-Wars does, draws its first frame into a drawable of the old size, and `captureScreenshot`'s `glReadPixels` leaves the rest of that frame as `malloc` gave it to LÖVE, which differs from one program and one run to the next; both runs set `MALLOC_PERTURB_`, so glibc fills that memory with the same byte in both.

SDL shows a dialog on Linux with zenity, a program of its own, when zenity is installed, and otherwise in a window of its own X11 toolkit, on a connection of its own to the X server, so no code in the game's process can press a key on it: both runs load `liblota_dialogs` (`ext/lota/native_test/answer_dialogs_linux.cpp`) with `LD_PRELOAD` too, whose `SDL_ShowMessageBox` and `SDL_ShowSimpleMessageBox` come before SDL's and, once the harness asks, answer each dialog with the button SDL flags for Return, as Return would, without showing it, and count it, through LuaJIT's FFI on the Lua side and `LotaNativeTest.press_return_on_dialogs` on the Ruby side.

X11 has no program to activate, only windows, and leaves whether one takes focus as it opens to the window manager, so SDL's hints change nothing there that a run on CI's display, where nobody types, would notice; the `setGrabbed` test raises its window with SDL's hint to activate it on for that raise, and afterward gives keyboard focus up to whatever window the pointer is over. The tests also share one display with the games they start, and SDL answers another program's request for the clipboard without guarding against that program's window being gone, which Xlib's default error handler would turn into the end of the test run, so the test extension lets that one error pass in the tests' own process (`ext/lota/native_test/selections_linux.cpp`).

Under X11 a warp of the pointer reaches SDL only as the motion the X server sends to the window on top where the pointer lands, so a window of another check that opens over a parity run's would take the move its script made; `LOTA_PARITY_DISPLAY` names a display of the harness's own, which CI's Linux gate starts beside the tests' (`Parity.display`).

## Lövetest

`test/lovetest` holds LÖVE's own Lövetest tests (`vendor/love/testing`), translated to Ruby by ADR 001's rules and marked as Zlib snippets. They open a real window, as Lövetest does: SDL's offscreen driver cannot create a Metal or OpenGL context on macOS, so run them in a logged-in session, and on Linux on a display, where LÖVE draws with OpenGL, through Mesa's software renderer on CI's Xvfb, as LÖVE's Linux CI runs Lövetest. Each compares what Lota draws with LÖVE's expected image, by Lövetest's own rule.

## Using a checkout from a game

To try unreleased changes in a game, point the game at a checkout of Lota through Bundler. Clone Lota and build its extension as above (`bin/setup`, then `bundle exec rake compile`, which puts the compiled extension in the checkout's `lib/lota`), then point your game's `Gemfile` at the checkout:

```ruby
# Gemfile
source "https://rubygems.org"

gem "lota", path: "../lota"
```

Run `bundle install` in the game's folder, then `bundle exec lota run .`. Run `bundle exec rake compile` in the checkout again after each pull, since Bundler loads the checkout's `lib` as it is and builds nothing itself.
