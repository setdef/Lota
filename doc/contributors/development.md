<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Developing Lota

This page is for you if you build Lota from source, change it, or run its checks. To make a game with Lota, start with the [README](../../README.md) instead.

Lota runs LÖVE's C++ engine under Ruby, so a change can break in Ruby, in C++, in the build of LÖVE's engine, or in how a game behaves next to LÖVE. Lota's checks cover all four, and they take a while. This page gets you a working clone, names the few commands you run, and says what CI does after you push.

## Get the source

Clone with submodules, then run `bin/setup`:

```sh
git clone --recurse-submodules https://github.com/setdef/Lota.git
cd Lota
bin/setup
```

The submodules hold what Lota builds against. `vendor/love` is LÖVE's source at the commit Lota pins. `vendor/love-apple-dependencies` holds the prebuilt libraries LÖVE links on macOS, and `vendor/love-appimage-source` the Makefile LÖVE's Linux CI builds its libraries with.

`bin/setup` needs [mise](https://mise.jdx.dev). It does the rest:

- It installs the tools `mise.toml` pins: Ruby, CMake, Ninja, ccache, clang-format, clang-tidy, the REUSE tool, actionlint, shellcheck, and on Linux patchelf.
- It compiles Ruby, once, with the Rust `mise.toml` pins, because mise's precompiled Ruby for macOS has no ZJIT and `rake bench` measures it. Compiling needs ruby-build's [suggested build environment](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment). If you installed this Ruby before without ZJIT, `mise install --force ruby` replaces it.
- It runs `bundle install`, then `rake sources:fetch`, which downloads the source archives the precompiled gem carries, such as OpenAL Soft's, into `vendor/sources`, and keeps each only if its SHA-256 matches `ext/lota/licenses.rb`. On Linux it also downloads the release of each library LÖVE's Makefile builds. On Linux and macOS the downloads go into one cache that every checkout on the computer shares, `lota/sources` in `XDG_CACHE_HOME` (or `~/.cache`), one fetch at a time, and each checkout links them in file by file. The gate runs `sources:fetch` first, so it downloads only what no checkout here has fetched yet.
- It installs pre-commit's hooks and Lota's pre-push hook (below).

On Ubuntu, `bin/setup` first checks for the packages in `tasks/apt/build.txt`, which LÖVE's Linux CI installs too. If any are missing, it prints the `sudo apt-get install` command and stops. It never runs `sudo` itself.

## The commands you run

### Before every push: `rake prepush`

```sh
bundle exec rake prepush
```

The pre-push checks build what changed, then run every check that takes seconds and a slice of each slow one, in parallel lanes. They leave out the tests that run a whole game in a process of their own, most of the parity games, the generator's later runs over all of LÖVE, and most of the sanitized suite. `PREPUSH_LEAVES_OUT` and `PREPUSH_KEEPS` in `tasks/test.rake` name them, test by test. When you add or rename a slow test, update those lists; `test/tasks/rake_tasks_test.rb` fails when a name in them stops naming a test.

### The gate: `rake`

```sh
bundle exec rake
```

`bundle exec rake` is the gate, and it must pass with no errors and no warnings. It builds LÖVE's engine and Lota's extension, runs the tests (the native ones a second time under AddressSanitizer and UndefinedBehaviorSanitizer), the parity harness, RuboCop, RubyCritic, Steep, the signature and RDoc checks, REUSE, clang-format, clang-tidy, and the package checks. `bundle exec rake rubocop:autocorrect_all` first saves a round trip.

The checks run at once, in lanes (`tasks/gate.rake`). Each check's output prints whole when it ends, and the gate closes with a table of how long each check took. `LOTA_GATE_JOBS=1` runs them one after another.

Run the gate before you push a change to `ext/`, the bindings, the patches, packaging, or the parity harness, and before your last push of a session. CI runs it on every push anyway; running it first keeps trunk green.

### On a computer with no desktop

On Linux, the tests open their windows on X displays, one for each of the gate's lanes (`LOTA_GATE_DISPLAYS`). When `rake` runs a task that opens windows, such as the gate, `prepush`, `red_before_green`, or `test`, and nothing gives it displays, it starts four of its own and runs again inside them: Xvfb with Openbox, the first free displays from `:300` up, so checks running at once on one computer never share one. It ends them when it ends, however it ends. So `bundle exec rake` and the pre-push hook need nothing set up for them on a headless machine, a CI runner, or a container, beyond the packages `bin/setup` asks for. CI's Linux jobs start their own displays and set `LOTA_GATE_DISPLAYS`, and `rake` uses those.

Inside its displays `rake` also sets what the checks need with no desktop, unless you set it first: `LP_PERF=no_rast_linear`, because Mesa's llvmpipe after 24.0.5 reads the wrong uniform elements in its linear rasterizer; `LOTA_PARITY_CACHE=0`, as on CI; a desktop input lock of the run's own, kept quiet; a session bus where there is none; and, when ccache is on the `PATH`, CMake's builds compile through it. Unless the displays draw with Vulkan, it runs under `bwrap`, where installed, with Vulkan's drivers hidden, since Vulkan cannot present on Xvfb.

`LOTA_HEADLESS=1` starts the displays even on a desktop, so no window opens there, and `LOTA_HEADLESS=0` never starts them. `LOTA_GATE_GPU` chooses where they draw: `off` is Xvfb on llvmpipe, as on CI; `opengl` gives each display a weston of its own, whose headless backend renders on the GPU at `/dev/dri/renderD128`, with a rootful Xwayland in it as the X display; `vulkan` does the same with Vulkan visible. The GPU modes need weston, Xwayland, glxinfo, and for `vulkan` vulkaninfo, and fall back, saying why, to Xvfb, or from `vulkan` to `opengl` when the GPU has no Vulkan driver.

### The Windows checks, on a Windows computer of your own

The gate does not run on Windows, so CI checks Windows after you push. A change to the native code, the build, or anything of Windows' own can break there alone. If you have a Windows computer with MSYS2's UCRT64 environment and RubyInstaller's x64 Ruby, you can run Lota's Windows checks on it first. From the checkout's root, in a UCRT64 shell on the computer's desktop, run:

```sh
bash .github/windows_prepush.sh
```

It takes CI's Windows steps for x64: it builds LÖVE's libraries, the engine, and the extensions, checks their warnings and DLLs, opens a window, and runs the tests with the pre-push tier's slow tests left out. It prints each step and how long the run has taken, and exits with the first failure's status. [windows.md](windows.md) says what it leaves out and why.

### Each new test must fail first: `rake red_before_green`

A test you never saw fail proves nothing. `bundle exec rake red_before_green` runs each test your unpushed commits add or change against each commit's parent's `lib/`, `ext/`, `exe/`, `tasks/`, and `bin/`. It prints each test as `red`, with the first line of its failure, or as `NEVER RED`, which fails the task. Pass a range as `git rev-list` takes it to check other commits.

It works in your checkout, which must be clean in those folders and in `test/`, and it puts them back afterward. It skips a commit whose parent's engine differs from `HEAD`'s, since rebuilding LÖVE's engine is slow. It checks the tests `rake test` runs and the parity harness's own unit tests, which `PARITY_UNITS` in `tasks/test.rake` names. It skips the parity games and `test/sanitizers`, which need the reference `love` or the sanitized build, and marks `unchecked` any test that stops because the reference `love` is not built.

A commit that changes no behavior, such as a refactor or tests of behavior already there, waives the check with a trailer above `Provenance:` that says why:

```
Red-before-green: none (refactor)
```

### The pre-push hook

`bin/setup` installs a hook that runs `rake prepush`, then `rake red_before_green` over exactly the commits you push, before git sends anything. It runs them here, in the clone you push from. It prints each check and how long it took, and refuses the push if one fails (`.githooks/pre-push` and `tasks/prepush.rb`). It also refuses the push when a check changed a tracked file, as RuboCop's autocorrection does, since CI's gate fails then too; it puts back what the check changed and keeps any edit you made before. It does not run the Windows checks; CI does, after the push, unless you ran them yourself first (above).

Pushing a tag or deleting a ref runs nothing. git hands the hook the refs it pushes on standard input, and a hook that runs Lota's, such as a global one in `core.hooksPath`, can read them first. So when the hook gets no refs while `HEAD` has commits the remote lacks, it refuses the push rather than check nothing. In an emergency, such as pushing a revert to a red trunk, `LOTA_PREPUSH=skip git push` skips the checks.

The hook lives in the clone's shared hooks folder as a stub that runs `.githooks/pre-push` from whichever worktree pushes, so every worktree has it. `bin/setup` leaves alone a `pre-push` it did not write, and says so.

### Other tasks

`bundle exec rake -T` lists them all. These are the ones you meet most:

- `rake compile` builds the engine and the extensions and copies `Lota::Native` into `lib/lota`. CMake decides what to rebuild, so a build with no changes takes a second or two. On Linux, `tmp/` records the compilers that built it, and when they change, as when a distribution moves to a newer GCC, `rake` removes `tmp/` once and builds from scratch rather than fail in CMake's `project()`.
- `rake test` runs the tests; `rake test:native` runs the native suite under the sanitizers, in a build of its own in `tmp/sanitize`; `rake test:parity` runs the [parity harness](parity.md).
- `rake bindings:generate` writes the generated bindings, signatures, and `lib/lota/error_message/names.rb` from LÖVE's `wrap_*.cpp` files and the rules in `ext/lota/bindings.rb`. Never edit what it writes. `rake bindings:check` fails until the committed files match, and `rake "bindings:report[tmp/report.txt]"` lists every LÖVE function that fits no rule or several. [engine.md](design/engine.md) says how the bindings hold LÖVE's objects.
- `rake engine:sources` regenerates the list of LÖVE sources the engine compiles on this platform, after a bump of `vendor/love`; `engine:sources:check` fails until you do.
- `rake ios:sdl3`, `rake android:deps`, and `rake android:sources` build for phones, as [the phone guide](../guide/phones.md) describes. The gate runs none of them.
- `rake package:native` builds the precompiled gem for this platform, and `package:check` and `package:install` check it, as [ci.md](ci.md) describes.
- `rake cpp` runs clang-format and clang-tidy over Lota's C++, and `rake cpp:format:fix` fixes the layout.
- `rake lint:workflows` checks `.github/workflows` with actionlint and shellcheck.
- `rake bench` times draw calls in Lota and in LÖVE.

## What CI does after you push

GitHub Actions runs the gate on every push, on macOS and on Linux for x86_64 and arm64. It then installs each platform's gem on a fresh runner and runs Lövetest from it, builds and tests the Windows gems, builds phone apps in the iOS Simulator and an Android emulator, builds the iOS kit, and fuses three games into apps on all five platforms. Each push to trunk first gets the pre-push checks on macOS, Linux, and Windows, and `red_before_green` over the commits it brings, within about fifteen minutes. A red job on trunk stops all other work until it is fixed or reverted, and `bin/trunk-watch`, left running, reverts a single bad commit by itself. [ci.md](ci.md) has the details.

## Try a checkout in a game

To try unreleased changes in a game, point the game at your checkout. Run `bundle exec rake compile` in the checkout, then name it in the game's `Gemfile`:

```ruby
# Gemfile
source "https://rubygems.org"

gem "lota", path: "../lota"
```

Run `bundle install` in the game's folder, then `bundle exec lota run`. Bundler loads the checkout's `lib` as it is and builds nothing, so run `rake compile` in the checkout again after each pull.

## Read more

- [AGENTS.md](../../AGENTS.md) holds the project's rules: design precedence, provenance, and how to commit.
- The [ADRs](adr/) record the decisions that shape Lota, starting with [ADR 004](adr/004.md).
- The [design documents](design/) say how Lota works: [translation.md](design/translation.md) for the naming rules, [engine.md](design/engine.md) for the engine, its patches, bindings, and threads, [game.md](design/game.md) for how a game runs, and [packaging.md](design/packaging.md) for gems and `lota fuse`. Each patch in `ext/lota/engine/` says in its header what it changes and why.
- [parity.md](parity.md) covers Lövetest, the parity harness, and how tests share your desktop.
- [ci.md](ci.md) covers continuous integration and `bin/trunk-watch`.
- [windows.md](windows.md) covers how Lota builds and tests on Windows.
- [releasing.md](releasing.md) says how a release is cut.
- [upstream/](upstream/) holds the reports Lota would file with LÖVE.
