<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Continuous Integration

Lota ships for five desktop platforms and builds for two phone systems, and nobody's computer runs all of them. So every push to trunk runs every platform GitHub's free runners can run, and a red job there stops all other work until it is fixed or reverted. This page says what each workflow checks, and how `bin/trunk-watch` keeps trunk green.

## What runs on a push

`.github/workflows/ci.yml` runs on every push and pull request. A push to a branch cancels the run before it on that branch; a run on trunk is never cancelled. Its jobs:

- **Gate**, on macOS 15 on Apple Silicon (`macos-15`), and **Gate (x86_64-linux-gnu)** and **Gate (aarch64-linux-gnu)** on Ubuntu 22.04. Each runs `bundle exec rake`, fails if the gate changed a file (its autocorrect would otherwise pass unnoticed), and builds the precompiled gem with `rake package:native` as an artifact.
- **Delivery**, one for each of those three, which installs that gem on a fresh runner and runs Lövetest from it.
- **Windows build** for x64 and ARM64, which calls `windows.yml` to build and test the Windows gems without the gate, and **Delivery** for each ([windows.md](windows.md)).
- **Phones**, which calls `phones.yml`.
- **iOS kit** and **iOS kit, called as a game's CI calls it**, which call `ios-kit.yml` and `ios-kit-caller.yml`.
- **Fuse**, which calls `fuse.yml` with the gems this run built, once they are built.
- **Release**, which runs only for a tag, and publishes the gems only when every job above passed ([releasing.md](releasing.md)).

## The gate jobs

The macOS runner's session is logged in, so the tests open real windows there as on your Mac. The Linux runners draw on Xvfb displays with Openbox, as LÖVE's own Linux CI runs Lövetest, and cache the libraries `rake dependencies` builds. Compiled objects come from ccache, which reuses one only when the compiler, its arguments, and every file it reads are the same.

`LOTA_GATE_DISPLAYS` gives each of the gate's lanes its own X display on Linux, in `tasks/gate.rake`'s order. The Linux gate starts one for each lane that opens windows ([parity.md](parity.md) says why a lane needs its own).

On trunk, after the gate, the x86_64 Linux job runs `rake red_before_green` over the commits the push brings ([development.md](development.md)).

### When a lane hangs

GitHub ends a step that runs past its time and prints nothing about why. So the gate ends a hung lane itself, first. Each lane may run 47 minutes (`LOTA_GATE_LANE_TIMEOUT`, in seconds): the macOS Gate step may run 55, the gate spends up to about three and a half building before its lanes start, and its diagnosis takes up to about two. `Gate::LANE_TIMEOUT` in `tasks/gate.rb` keeps the arithmetic.

While lanes run, the gate prints a line, stamped in UTC, as each check starts and ends, and every minute (`LOTA_GATE_HEARTBEAT`) names each check still running and how long it has run. A lane past its budget is diagnosed: the gate prints the check's output so far, every process under it as `ps` lists them, and a one-second stack sample of each, taken with `/usr/bin/sample` on macOS and with `eu-stack` or `gdb` on Linux where either is installed. Then it ends the check's process group and fails the check as TIMED OUT.

### Tools

CI takes its Ruby from `ruby/setup-ruby` rather than mise, and mise skips Ruby and the Rust that compiles it. setup-ruby's Ruby is built by ruby-build with Rust, so it has ZJIT without compiling Ruby on every run. mise's installs are cached under a key of `mise.toml`'s hash, but mise itself, and MSYS2's base on Windows, download from GitHub's releases on every run. A job that fails to set either up tries again after a pause, twice for mise (`.github/actions/mise`) and once for MSYS2, so an outage of those downloads does not stop trunk.

## The gem's checks

The gate and the delivery jobs check the gem a game installs, not only the code that builds it ([packaging.md](design/packaging.md)).

`rake package:native` builds the precompiled gem for the platform it runs on (`tasks/native_gem.rb`). It carries the extension, the libraries it loads (frameworks on macOS, shared libraries on Linux, with their rpaths pointed into the gem), and a record of who wrote them under which licenses, by the REUSE Specification, written from `ext/lota/licenses.rb`. A library or source file that record does not name stops the build, and so does a gem `reuse lint` does not call compliant. OpenAL Soft's source archive goes into the gem, as its license asks.

`rake package:check` checks that the source gem's install stops with a message naming the precompiled gems, runs `reuse lint` on the precompiled gem's unpacked package, checks each source archive the record names, and loads the gem.

`rake package:install` builds the gem and delivers it, as `rake "package:deliver[path/to/gem]"` delivers a gem built elsewhere. It installs the gem into an empty `GEM_HOME`, runs `lota --version`, and runs `lota run` on two games: one that opens a window and quits with a status of its own, and `test/lovetest/game`, which runs the translated Lövetest against LÖVE's expected images. Each run plays sound to OpenAL Soft's null backend, must end with its expected status and output, and must load Lota and its libraries only from the installed gem, never from the repository's `lib/`. Both tasks fail on any warning `gem build` prints. The Delivery jobs run `package:deliver` on a runner that builds nothing.

## Phones

`phones.yml` takes the steps of [the phone guide](../guide/phones.md) on Lota's sample game, `test/games/phone`. On macOS it builds the Xcode project with Fledge, builds it for the Simulator and for devices, Debug and Release, with signing off, archives it, and runs the game in an iPhone 17 Pro and an iPad Pro 13-inch (M5) Simulator. On Ubuntu 24.04 it builds the Gradle project with the NDK, builds a debug APK, a release APK, and an App Bundle, signs the release builds with a key made for the run, and runs the debug APK on `x86_64` emulators of Android 16 (API 36) and Android 13 (API 33), sending the game home and back. A game that prints, draws, plays its tone, saves a file, and quits with status 0 passes. `test/tasks/phone_host_test.rb` checks the hosts against the engine: that the Activity loads every shared library the Android engine links, and has every method LÖVE's `src/common/android.cpp` calls on it.

No free runner boots an arm64 emulator, and no runner has a device, so nothing in CI runs the `arm64-v8a` build or a device build.

## The iOS kit

`ios-kit.yml` builds any Lota game's Xcode project from Lota's iOS host, for a game's own CI to call ([the phone guide](../guide/phones.md) shows the call). Its scripts are in `ipad/`. Lota's CI calls it on every push for `test/games/winkit`, and through `ios-kit-caller.yml` for `test/games/sample_game` exactly as a game's CI would, with `uses: ./.github/workflows/ios-kit.yml` and `lota_ref: ${{ github.sha }}`, the workflow of the same commit. A tag releases nothing unless both kits pass.

### What it checks

Three jobs run on `macos-15` with the newest Xcode there:

1. **The project.** It builds SDL3 for iOS, lays the game out (`ipad/prepare.rb`), runs `fledge build ios`, fails if anything Xcode reads names a path on the runner, and uploads the kit.
2. **A fresh Mac, in portrait.** A second runner, with no Lota, Fledge, XcodeGen, or bundle, unpacks the zip and builds it for the Simulator and, with signing off, for devices, Debug and Release. `ipad/check_app.rb` reads each built `Info.plist`: the display name character for character, the identifier, the device families, the orientations, the status bar, the launch screen, the input and audio keys, and the icon. `ipad/simulator.rb` then runs the app in an iPad Pro 13-inch, an iPad (A16), an iPad mini, an iPhone 17 Pro, and an iPhone 16e when the runtime has one: on each, two normal launches and one idle launch, keeping screenshots, the app's log, its data container, and any crash report.
3. **Landscape, touch, and rotation.** A third runner adds a UI test target to a copy of the project, which the kit never holds. A UI test turns each Simulator to landscape and holds it there while `simctl` runs the same launches. On the iPad Pro and the iPhone 17 Pro a second UI test taps known points in portrait, turns the device, taps again, and turns it back, with a screenshot at each stage. XCTest never launches the app itself, since its launch sets `OS_ACTIVITY_DT_MODE` and the game's output would miss the log.

A launch passes when no crash report appears, no line holds `[BUG]`, and the app either exits with status 0 or is still running when its time is up. A normal launch's output must also match `smoke_expect` when a caller gives one. Each job writes its verdicts to `results-portrait.json` or `results-landscape.json`.

`test/games/winkit`'s probe (`WINKIT_DPI_PROBE=1`) prints the window's scale, its sizes in units and pixels, its safe area, and where each tap landed, and the push run taps with it on, so a change to how touches map to pixels shows up there.

### Why the host sets what it sets

`ext/lota/phone/host/ios` is the host the kit and the phone guide both use. Each choice keeps a lesson the first kits taught:

- **`OS_ACTIVITY_DT_MODE` stays unset.** With it in the environment, whatever its value, the unified log copies every entry to standard error, and forwarding standard error to the log would feed the app its own output until it froze. The host and Fledge's runtime both leave the streams alone when it is set, and the kit's scheme never sets it. Xcode's console and XCTest's launches do set it, so their output stays on the app's own streams.
- **Standard output is in sync mode.** Fledge's runtime puts `$stdout` in sync mode whenever it is not a terminal, as on a phone it never is, so a game's lines reach the log as it prints them.
- **SDL's accelerometer joystick is off.** SDL shows the accelerometer as a joystick on iOS, and LÖVE leaves it so. An early Lota crashed while a game read that joystick every frame, so the host sets `SDL_ACCELEROMETER_AS_JOYSTICK=0` unless the environment already sets it. A game reads the accelerometer through `Lota::Sensor`.
- **The audio session is ambient by default**, as a game's usually is: it mixes with other apps' audio, and the silent switch mutes it.

### What no run proves

No Simulator signs, installs over a cable, reads a real accelerometer, or plays through a speaker. Whether the device build signs, installs, runs at the device's frame rate, sounds right, and honours the silent switch is found out on a device, and the playtest questions the kit carries ask about it.

## Fuse

`fuse.yml` checks `lota fuse` ([packaging.md](design/packaging.md)) on a runner of each of the five platforms. It installs the gem this CI run built, and fuses three games with the checkout's `lota fuse`: `test/games/fuse`, with no Gemfile; `test/games/fuse_gems`, whose lockfile locks an older gem than its Gemfile allows; and `test/games/fuse_native`, which asks for a C extension. It unpacks each app under a folder whose name has a space, runs it with no Ruby on its `PATH`, and checks with `.github/fuse_check.rb` that it quit with 3, ran fused, saved under its identity alone, played a sound, and printed what only its gems print. A job of its own fuses `fuse_native` in Ruby's Debian image, which has no compiler, and checks that `lota fuse` fails and says what to install. Linux runs on Ubuntu 24.04, since Fledge's Linux runtime needs glibc 2.39.

Run by hand, it fuses another public game instead (`game_repository`, `game_ref`, `game_path`), and on x64 Windows runs the app for up to 50 seconds on llvmpipe, keeping what it printed and screenshots of the desktop.

## Keeping trunk green: `bin/trunk-watch`

```sh
bin/trunk-watch [--interval SECONDS] [--no-revert] [FLOOR_RUN_ID]
```

`bin/trunk-watch` watches trunk's runs with `gh` and is trunk's automatic revert, the backstop for a commit the local gate let through. Every three minutes it lists the failed runs above `FLOOR_RUN_ID` and reads each one's failed log:

- A run whose every error is a download or a runner breaking, such as a curl failure, an HTTP 5xx, or a lost runner, runs again, up to its third attempt. `TrunkWatch::OUTAGE` in `tasks/trunk_watch.rb` lists the outages it knows.
- Any other failure has its failed jobs run again once, so a flaky test cannot revert a good commit. If that passes, the watch prints that it passed on rerun, a likely flaky test worth fixing, and goes on.
- A run still red after its rerun sends the watch looking for the commits between the last commit the red run's own workflow passed on and the red one, so a workflow cancelled on an older commit does not hide the culprit. If there is exactly one, and it is not a merge, the watch reverts it in a scratch clone of its own, never your working copy, pushes the revert to trunk without force, prints `REVERTED sha (run ID)`, and exits 1, so whoever ran it in the background is woken to tell the commit's author.
- With several commits, a merge, a conflict, or an outage that will not clear, it reverts nothing. It prints `TRUNK RED` with the run, the commit range, and the first errors, and exits 1, and someone bisects.

`--no-revert` reruns nothing and reverts nothing: any failure that is not an outage stops the watch with `TRUNK RED`. The watch exits 0 on SIGINT or SIGTERM. Its decisions are pure functions in `tasks/trunk_watch.rb` (`classify` and `plan`), tested with recorded `gh` and `git` output.
