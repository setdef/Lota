<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Continuous Integration

Lota ships for five desktop platforms and builds for two phone systems, and nobody's computer runs all of them. So trunk runs every platform GitHub's free runners can run, and a red job there stops all other work until it is fixed or reverted. This page says what each workflow checks, and how the automatic revert and `bin/trunk-watch` keep trunk green.

## What runs on a push

Two workflows check trunk. The pre-push tier runs on every push and answers first, in about fifteen minutes. The full run takes an hour or more, much of it waiting for macOS runners, so it runs on the newest push that has arrived when the run before it ends.

`.github/workflows/prepush.yml` runs `bundle exec rake prepush` ([development.md](development.md)) on `macos-15` and on Ubuntu 22.04 for x86_64, set up as the gate jobs below are, and the Windows build and tests on x64 (`windows.yml`, below), which take about as long. Its x86_64 Linux job then runs `rake red_before_green` over the commits the push brings. It is a workflow of its own because GitHub finishes a run, and `bin/trunk-watch` reads it, only when its last job ends, and the full run's phone and iOS kit jobs end an hour or more after its desktop jobs. Each trunk commit gets a run of its own, never cancelled, so the watch can judge each commit against its parent and name the one that broke the tier.

`.github/workflows/ci.yml` runs on every push and pull request. A push to a branch cancels the run before it on that branch. A run on trunk is never cancelled once it starts, but only the newest push waits for it: GitHub cancels a waiting run when a newer push joins the queue. A run asks for about eight macOS jobs, some 175 runner-minutes, and GitHub's free plan runs five macOS jobs at once, so a run for every commit would queue hours deep, with the tier's macOS job behind it. The one exception is a run started with the input `release_tag`, which proves a release commit: it waits in a queue of its own, so no push cancels it. Its jobs:

- **Gate**, on macOS 15 on Apple Silicon (`macos-15`), and **Gate (x86_64-linux-gnu)** and **Gate (aarch64-linux-gnu)** on Ubuntu 22.04. Each runs `bundle exec rake`, fails if the gate changed a file (its autocorrect would otherwise pass unnoticed), and builds the precompiled gem with `rake package:native` as an artifact.
- **Delivery**, one for each of those three, which installs that gem on a fresh runner and runs Lövetest from it.
- **Windows build** and **Delivery** for x64 and ARM64, which build and test the Windows gems without the gate ([windows.md](windows.md)). The build and its tests are `windows.yml`, which the pre-push tier calls too.
- **Phones**, which calls `phones.yml`.
- **iOS kit**, which calls `ios-kit.yml` for `test/games/winkit`, and **iOS kit, called as a game's CI calls it**, which calls `ios-kit-caller.yml`. The second runs only for a tag and by hand; a push does not run it (see the iOS kit, below).
- **Fuse**, which calls `fuse.yml` with the gems this run built, once they are built.
- **Prepare the next release**, which runs on a push to trunk once every job above that a push runs passed. When trunk has not moved on and CHANGELOG.md's `[Unreleased]` lists changes, it commits the release to trunk and starts CI on that commit with `release_tag` ([releasing.md](releasing.md)). Its failures stop the release, not trunk, so the run stays green when it fails.
- **Release**, which runs for a tag, for a run started with `release_tag`, and by hand as a dry run. It tags the commit, for `release_tag`, and publishes the gems only when every job above passed, the iOS kit called as a game's CI calls it among them ([releasing.md](releasing.md)).

## The gate jobs

The macOS runner's session is logged in, so the tests open real windows there as on your Mac. The Linux runners draw on Xvfb displays with Openbox, as LÖVE's own Linux CI runs Lövetest, and cache the libraries `rake dependencies` builds. Compiled objects come from ccache, which reuses one only when the compiler, its arguments, and every file it reads are the same.

`LOTA_GATE_DISPLAYS` gives each of the gate's lanes its own X display on Linux, in `tasks/gate.rake`'s order. The Linux gate starts one for each lane that opens windows ([parity.md](parity.md) says why a lane needs its own).

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

`ios-kit.yml` builds any Lota game's Xcode project from Lota's iOS host, for a game's own CI to call ([the phone guide](../guide/phones.md) shows the call). Its scripts are in `ipad/`. Lota's CI calls it on every full run for `test/games/winkit`, and through `ios-kit-caller.yml` for `test/games/sample_game` exactly as a game's CI would, with `uses: ./.github/workflows/ios-kit.yml` and `lota_ref: ${{ github.sha }}`, the workflow of the same commit. The two copies together take about two thirds of a full run's macOS minutes, so the second runs less often: for a tag, by hand (`workflow_dispatch` of CI or of `ios-kit-caller.yml`), and every day at 06:17 UTC on trunk, which is `ios-kit-caller.yml`'s own schedule. A push does not run it, since the winkit copy has just run the same workflow. A tag releases nothing unless both kits pass: the release job needs both, and a tag runs both. A red scheduled run is a red run on trunk like any other, and `bin/trunk-watch` sees it.

### What it checks

Three jobs run on `macos-15` with the newest Xcode there:

1. **The project.** It builds SDL3 for iOS, lays the game out (`ipad/prepare.rb`), runs `fledge build ios`, fails if anything Xcode reads names a path on the runner, and uploads the kit.
2. **A fresh Mac, in portrait.** A second runner, with no Lota, Fledge, XcodeGen, or bundle, unpacks the zip and builds it for the Simulator and, with signing off, for devices, Debug and Release. `ipad/check_app.rb` reads each built `Info.plist`: the display name character for character, the identifier, the device families, the orientations, the status bar, the launch screen, the input and audio keys, and the icon. `ipad/simulator.rb` then runs the app in an iPad Pro 13-inch, an iPad (A16), an iPad mini, an iPhone 17 Pro, and an iPhone 16e when the runtime has one: on each, two normal launches and one idle launch, keeping screenshots, the app's log, its data container, and any crash report.
3. **Landscape, touch, and rotation.** A third runner adds a UI test target to a copy of the project, which the kit never holds. A UI test turns each Simulator to landscape and holds it there while `simctl` runs the same launches. The first UI test on a fresh runner has spent seven minutes starting and then never connected, so one that has not turned its device in seven minutes is started once more before the device fails. On the iPad Pro and the iPhone 17 Pro a second UI test taps known points in portrait, turns the device, taps again, and turns it back, with a screenshot at each stage. XCTest never launches the app itself, since its launch sets `OS_ACTIVITY_DT_MODE` and the game's output would miss the log.

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

`fuse.yml` checks `lota fuse` ([packaging.md](design/packaging.md)) on a runner of each of the five platforms. It installs the gem this CI run built, and fuses three games with the checkout's `lota fuse`: `test/games/fuse`, with no Gemfile; `test/games/fuse_gems`, whose lockfile locks an older gem than its Gemfile allows; and `test/games/fuse_native`, which asks for a C extension. It unpacks each app under a folder whose name has a space, runs it with no Ruby on its `PATH`, and checks with `.github/fuse_check.rb` that it quit with 3, ran fused, saved under its identity alone, played a sound, and printed what only its gems print. `test/games/fuse` also opens a window and draws the screen Lövetest's captureScreenshot test captures, with Lövetest's logo and font, and saves a screenshot of it, which the check compares with Lövetest's expected image by Lövetest's rule (`tasks/lovetest_image.rb`). It draws with Metal on macOS, and on Mesa's llvmpipe on Linux, under Xvfb with Openbox, and on Windows, where Mesa's `opengl32.dll` from MSYS2 goes beside the app's program once the app is built. A job of its own fuses `fuse_native` in Ruby's Debian image, which has no compiler, and checks that `lota fuse` fails and says what to install. Linux runs on Ubuntu 24.04, since Fledge's Linux runtime needs glibc 2.39.

Run by hand, it fuses another public game instead (`game_repository`, `game_ref`, `game_path`), and on x64 Windows runs the app for up to 50 seconds on llvmpipe, keeping what it printed and screenshots of the desktop.

## Keeping trunk green

A commit the pre-push checks let through can still break a full run, and a full run takes an hour or more and holds every commit pushed while the run before it went on. Waiting for someone to bisect leaves trunk red for everyone meanwhile, so two backstops revert instead: the automatic revert, in CI, for red full runs, and `bin/trunk-watch`, which you run yourself.

### The automatic revert

`.github/workflows/revert.yml` runs `bin/auto-revert` on a red full run on trunk (`tasks/auto_revert.rb`):

- On the run's first failed attempt, it runs the failed jobs again, so a flaky test cannot revert a good commit. When they pass, nothing more happens. When the rerun is itself superseded by a newer push, the newer run, which holds the same commits, is judged in its place.
- When every error of a later attempt is an outage, as `bin/trunk-watch` tells them (below), it runs the failed jobs again up to the third attempt, and after that tells people and reverts nothing.
- When the failed jobs fail again, it reverts every commit since the last commit whose run of the same workflow passed, the whole batch the run brought in, since nothing tells which of them broke trunk. It reverts them in one commit, on top of trunk as it is then, and pushes it without force, rebasing and trying again when trunk moves first. The commit's message names the run, the jobs that failed twice, and each commit, and its trailers are `Reverts` (the commits), `Red-run`, `Red-jobs`, `Red-before-green: none (revert)`, and `Provenance: requested`. A push GitHub's token makes starts no workflow, so it then starts CI and the pre-push tier on trunk by hand.
- The revert commit is the notice: its message names the red run, the jobs that failed twice, and each reverted commit with its author, and the revert run's summary repeats it. It opens no issue and writes no comment.
- It never reverts a revert, which could put back what broke trunk and loop, and never CI's release bookkeeping ([releasing.md](releasing.md)), which it leaves out of the batch. It reverts nothing when trunk already holds a fix: a later commit whose run passed, or a later revert, whose own run judges what is left. A merge, more than 30 commits, a history that reaches no green commit, or a revert that does not apply goes to a person: it reverts nothing, and fails with the run, the jobs, and each commit and its author in its summary.

Run by hand, with the id of a run on any branch, it does the same for that run. As a dry run, the default, it starts no run on the revert, so it rehearses on a branch:

```sh
gh workflow run revert.yml --ref experiment/revert -f run_id=RUN_ID -f dry_run=true
```

For now it runs only by hand; it is started on every red full run on trunk once a rehearsal on a branch has reverted a red commit there.

### `bin/trunk-watch`

```sh
bin/trunk-watch [--interval SECONDS] [--no-revert] [FLOOR_RUN_ID]
```

`bin/trunk-watch` watches trunk's runs of every workflow with `gh`, from your machine, and reverts a single bad commit by itself. Every three minutes it lists the failed runs above `FLOOR_RUN_ID` and reads the log of each failed job:

- A run whose every error is a download or a runner breaking, such as a curl failure, an HTTP 5xx, or a lost runner, runs again, up to its third attempt. `TrunkWatch::OUTAGE` in `tasks/trunk_watch.rb` lists the outages it knows. An Android system image that arrived as a zip `sdkmanager` cannot open (`TrunkWatch::BROKEN_DOWNLOAD`) leaves only its step's exit status as an error, so in that job's log the exit status counts as the outage's too. Each job's log is judged alone, so one job's outage never excuses another job's failure.
- Any other failure has its failed jobs run again once, so a flaky test cannot revert a good commit. If that passes, the watch prints that it passed on rerun, a likely flaky test worth fixing, and goes on.
- A run still red after its rerun sends the watch looking for the commits between the red one and the last trunk commit whose runs of the same workflow all passed. The pre-push tier runs on every commit, so its red run usually names one. If there is exactly one, and it is not a merge, the watch reverts it in a scratch clone of its own, never your working copy, pushes the revert to trunk without force, prints `REVERTED sha (run ID)`, and exits 1, so whoever ran it in the background is woken to tell the commit's author.
- With several commits, a merge, a conflict, or an outage that will not clear, it reverts nothing. It prints `TRUNK RED` with the run, the commit range, and the first errors, and exits 1, and someone bisects.

`--no-revert` reruns nothing and reverts nothing: any failure that is not an outage stops the watch with `TRUNK RED`. The watch exits 0 on SIGINT or SIGTERM. Its decisions are pure functions in `tasks/trunk_watch.rb` (`classify` and `plan`), tested with recorded `gh` and `git` output.
