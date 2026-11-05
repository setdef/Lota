<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The iOS kit: an Xcode project for any Lota game

Apple permits no generic player app on iOS, so a Lota game reaches an iPhone or iPad the way a LÖVE game does: as an Xcode project that someone opens, signs, and runs. The newcomer and the studio both need that project (plan 002, "Two ends of shipping a game"). The studio needs it most: it ships a game as an app of its own, so it opens the project, brands it, signs it with its own team, and builds it from source.

Making that project by hand takes Lota built for two iOS slices, SDL3 built static, Fledge's Ruby runtime, an SDL host program, and XcodeGen. The iOS kit workflow does all of that on CI for a repository that holds a Lota game, checks the result in iPhone and iPad Simulators, and hands you a zip. Lota builds the kit; you run it, in your own game's CI. To open the kit you need a Mac with Xcode and an Apple ID, and no Ruby, Lota, Fledge, or XcodeGen.

The workflow is `.github/workflows/ios-kit.yml`, with its scripts in `ipad/`, on the throwaway branches `experiment/ios-kit-*`, while the iOS route is an experiment. Lota checks it with its own sample games, `test/games/winkit` and `test/games/moon_pong`.

## Run it in your game's CI

Add one workflow to your game's repository. It calls Lota's as a reusable workflow, so your CI copies no scripts: it names Lota's ref twice, in `uses` and in `lota_ref`, and the two must match.

```yaml
# .github/workflows/ios-kit.yml in your game's repository
name: iOS kit

on:
  workflow_dispatch:
  push:
    tags: ["v*"]

permissions:
  contents: read
  actions: read

jobs:
  ios-kit:
    uses: setdef/Lota/.github/workflows/ios-kit.yml@experiment/ios-kit-1
    with:
      lota_ref: experiment/ios-kit-1
      game_repository: ${{ github.repository }}
      game_ref: ${{ github.sha }}
      display_name: "Moon Pong ’em"
      identifier: com.example.moonpong
      icon: icons/icon-*.png
      smoke_env: MOON_PONG_QUIT_AFTER=12
```

The jobs run on your repository's macOS runners, and the artifacts land on your run. Because the game comes through `actions/checkout` with your run's token, your repository may be private. Lota's own `.github/workflows/ios-kit-caller.yml` is this call, made for Moon Pong ’em, and it runs when `experiment/ios-kit-call-*` is pushed.

## Make a kit from Lota's repository

Lota's maintainers can also dispatch the workflow in Lota's repository for a public game repository:

```sh
gh workflow run ios-kit.yml -R setdef/Lota --ref experiment/ios-kit-1 \
  -f game_repository=OWNER/NAME -f game_ref=v1.0.0 \
  -f "display_name=Moon Pong ’em" -f identifier=com.example.moonpong \
  -f icon=icons/icon-*.png
gh run watch -R setdef/Lota "$(gh run list -R setdef/Lota --workflow ios-kit.yml -L 1 --json databaseId -q '.[0].databaseId')"
```

When the run is green, download its `ios-kit` artifact: `gh run download RUN -R setdef/Lota -n ios-kit`. It holds `APP_NAME-ios.zip`, `kit.json` (what the run resolved from your inputs), and `SHA256SUMS`. Unpack the zip with `ditto -x -k` or Finder, which keep its symbolic links, and follow the `README.txt` inside: add your Apple ID, choose your team, set the bundle identifier, pair the device by cable, turn on Developer Mode, trust the developer, and press Run.

Pushing to an `experiment/ios-kit-*` branch builds Lota's own `test/games/winkit` from that commit, as the workflow's check of itself.

## Inputs

Every input but `game_repository`, and `lota_ref` in a call, has a default.

- **`game_repository`**, `OWNER/NAME` of the game's GitHub repository: in your own CI, `${{ github.repository }}`. The run's token checks it out, so it reads your own repository even when it is private, and any public one.
- **`lota_ref`**, in a call from your CI, the ref of Lota your `uses` line names. Dispatched in Lota's repository, it defaults to the run's own commit.
- **`game_ref`**, a tag, branch, or commit; empty for the default branch.
- **`game_path`**, the game's folder in the repository, the one with `main.rb`; `.` by default.
- **`display_name`**, the name under the icon (`CFBundleDisplayName`). It may hold spaces and any Unicode, such as a typographic apostrophe; it travels as the target's `APP_DISPLAY_NAME` build setting, through `project.yml`, XcodeGen, and Xcode's Info.plist processing. Empty takes the repository's name.
- **`app_name`**, the Xcode target's and the executable's name: ASCII letters and digits, a letter first. Empty derives it from `display_name`, so "Moon Pong ’em" becomes `MoonPongEm`.
- **`identifier`**, the bundle identifier; empty for `com.example.APP_NAME`, a placeholder you change when you sign.
- **`program`**, the Ruby program the app runs, relative to `game_path`. Empty writes `main.rb` beside a copy of the game folder, the entry script `lota fuse` writes (`lib/lota/fuse.rb`): `Lota::Boot.new(game_dir, ARGV, fused: true).call`. With a program named, the game folder itself is the project, and the program boots the game as it likes.
- **`icon`**, a folder, a glob such as `icons/icon-*.png`, or a PNG file, relative to the repository's root. The workflow takes the PNG of 1024 by 1024 pixels, from which Xcode makes every other size. With none, or none of that size, the app gets a plain generated icon (an orange disc on blue), and the run says so in a warning.
- **`orientations`**, as `iphone: portrait landscape; ipad: all`, which is the default. The words are `portrait`, `upside-down`, `landscape-left`, `landscape-right`, `landscape` (both), and `all`; a list without `iphone:` or `ipad:` sets both.
- **`audio_category`**, the audio session's category, set before SDL and OpenAL open the audio device: `ambient` (the default; mixes with other apps' audio, and the silent switch mutes it), `solo-ambient`, `playback`, or `default`.
- **`hide_status_bar`**, true by default: `UIStatusBarHidden`, with `UIViewControllerBasedStatusBarAppearance` false. On an iPhone that hides it. In the iPadOS 26.2 Simulator, a game whose window is not fullscreen still showed the status bar over its top edge, while an earlier kit's game with a fullscreen window showed none; a game that should cover the whole iPad screen sets `t.window.fullscreen = true`.
- **`smoke_env`**, **`smoke_expect`**, **`smoke_seconds`**, **`touch_env`**, and **`extra_launches`** shape only CI's Simulator runs, never the app the kit builds; see below.
- **`kit_questions`**, a plain-text file in the repository with your playtest's questions. A file whose every line but `#` comments reads `question | answer type` becomes numbered questions, each with an answer blank and a note blank: `y/n`, `yes/no`, and `yes/no + text` ask for y or n, `rating` for 1 to 5, and `choice: a/b/c` for one of those; `text` and any other type get a plain blank. Any other file is copied as it is. The kit carries them as `APP_NAME-results.txt`, under a header with blanks for the device model, the iOS version, and the date, and the game's repository, ref, and commit, Lota's commit, and the run already filled in. Empty uses a short generic questionnaire (`ipad/questions.txt`).
- **`project_run`**, a run whose `ios-kit` artifact the checks take instead of building a new one.

## What the kit holds

The zip is the project `fledge build ios` writes (Fledge 0.5.0), finished by `ipad/prepare.rb`:

- `APP_NAME.xcodeproj`, already generated, with one target for iPhone and iPad (`TARGETED_DEVICE_FAMILY` 1,2) and a shared scheme that sets no environment.
- `Host/main.m`, SDL's host: it runs the game's Ruby on the main thread inside `SDL_RunApp`, with a 64 MB stack, and sends the game's output to the unified log under the bundle identifier, category `ruby`.
- `Host/Info.plist`, with `UILaunchScreen`, so the app runs at the screen's own size; `UIApplicationSupportsIndirectInputEvents`, which SDL asks for to read a mouse or trackpad; the status bar and orientation settings; and `LotaAudioSessionCategory`. `UIRequiresFullScreen` stays unset.
- `FledgeRuby.xcframework` and `FledgeExtensions.xcframework`: Ruby, and Lota's engine with SDL3, for devices and the Simulator.
- `fledge/`, the game and Lota's gem. The gem is a folder of the paths `lota.gemspec` ships, not Lota's checkout.
- `README.txt`, `APP_NAME-results.txt`, and `BUILD-INFO.txt`, which names the game's commit, Lota's commit, Fledge's tag, Xcode, XcodeGen, and the run.

## The host's choices

Each of these keeps a lesson the first kits taught.

- **`OS_ACTIVITY_DT_MODE` stays unset.** With it in the environment, whatever its value, the unified log copies every entry to standard error, and forwarding standard error to the log would feed the app its own output until it froze. The host and Fledge 0.5.0's runtime both leave the streams alone when it is set, and the kit's scheme never sets it. Xcode's console and XCTest's own launches do set it, so their output stays on the app's streams rather than in the log.
- **Standard output is in sync mode.** Fledge 0.5.0's runtime leaves `$stdout` buffered, so the entry script the kit writes sets `$stdout.sync = true`, and a game's lines reach the log as it prints them. A game with its own program sets it there.
- **SDL's accelerometer joystick is off.** On iOS SDL shows the accelerometer as a joystick by default, and LÖVE leaves it so. An early Lota crashed while a game read that joystick every frame, so the host sets `SDL_ACCELEROMETER_AS_JOYSTICK=0`, as a guard, unless the environment already sets it. A game reads the accelerometer through `Lota::Sensor`, and a paired controller is still a joystick. Set the variable to `1` in the scheme to bring the joystick back.
- **The audio session is ambient by default**, as a game's usually is: it mixes with music from other apps, and the silent switch mutes it.

## What CI checks

Three jobs run on `macos-15` with the newest Xcode there.

1. **The project.** It builds SDL3 for iOS, lays the game out, runs `fledge build ios`, fails if anything Xcode reads names a path on the runner, and uploads `ios-kit`.
2. **A fresh Mac, in portrait.** A second runner, with no Lota, Fledge, XcodeGen, or bundle, unpacks the zip and builds it with `xcodebuild` for the Simulator and, with signing off, for devices, Debug and Release. `ipad/check_app.rb` reads each built `Info.plist`: the display name character for character, the identifier, device family 1 and 2, the orientations, the status bar, the launch screen, the input and audio keys, and the icon. `ipad/simulator.rb` then runs the app in an iPad Pro 13-inch, an iPad (A16), an iPad mini, an iPhone 17 Pro, and an iPhone 16e when the runtime has one, all in portrait: on each, two normal launches and one idle launch, with screenshots at several times, the app's log, its data container, and any crash report. It uploads `ios-kit-simulator`.
3. **Landscape, touch, and rotation.** A third runner adds a UI test target to a copy of the project, which the kit never holds, since its runner is a second app with a second App ID. A UI test turns each Simulator to landscape and holds it there while simctl runs the same launches. On the iPad Pro and the iPhone 17 Pro, a second UI test waits for the app, which simctl launches with `smoke_env` and `touch_env`, taps three known points in portrait, turns the device to landscape, taps two more, and turns it back, saving a screenshot at each stage. XCTest never launches the app itself, since its launch sets `OS_ACTIVITY_DT_MODE` and the game's output would miss the log. It uploads `ios-kit-touch`.

`extra_launches` adds portrait launches after those, separated by `;`, each with NAME=VALUE pairs of its own rather than `smoke_env`'s, such as a replay of a saved game; their output is kept in the results file.

A normal launch passes `smoke_env` to the app as `SIMCTL_CHILD_` variables and runs for up to `smoke_seconds` (20 by default); an idle launch has no settings and runs for 30 seconds or `smoke_seconds`, whichever is longer. A launch passes when no crash report appears, no line holds `[BUG]`, and the app either exits with status 0 or is still running when its time is up. A normal launch's output must also match `smoke_expect`, a Ruby regular expression, when you give one. So a game that quits by itself, such as through a setting in `smoke_env`, must quit with 0, and one that runs on passes by not crashing. Each job writes its verdicts to `results-portrait.json` or `results-landscape.json`.

Give your game a setting that makes it play itself and quit, and pass it in `smoke_env`; then CI sees more of it than a title screen.

## Points and pixels, and `usedpiscale`

With `t.highdpi = true` a game draws at the screen's own pixels; without it, as in LÖVE, it draws at 1x on a Retina screen. LÖVE's `usedpiscale` decides what units the game counts in. When it is false, `getDPIScale` returns 1.0 (`src/modules/window/sdl/Window.cpp`, `Window::getDPIScale`), and LÖVE converts a touch's normalized position by the window's size in those units (`src/modules/event/sdl/Event.cpp`, `normalizedToDPICoords`), so touch coordinates and `Lota::Window.safe_area` come in physical pixels, the same units as `Lota::Graphics.pixel_dimensions`, and `Lota::Graphics.dimensions` equals `pixel_dimensions`. A touch at a fraction of the screen reads that fraction of `pixel_dimensions`. Winkit's probe (`WINKIT_DPI_PROBE=1`) prints these values, and the workflow's push run taps known points with it on.

Run 42076270861 (Lota's winkit, iOS 26.2 Simulator, `usedpiscale: false`, `t.highdpi = true`) printed, verbatim:

```
iPad Pro 13-inch (M5), portrait:
probe: usedpiscale=false highdpi=true Window.dpi_scale=1.0 Window.native_dpi_scale=2.0 Graphics.dpi_scale=1.0 Graphics.dimensions=[2064, 2752] Graphics.pixel_dimensions=[2064, 2752] Window.safe_area=[0, 64, 2064, 2648]
probe: touch at 516.0, 688.0 is 0.25, 0.25 of pixel_dimensions 2064x2752
probe: touch at 1548.0, 1376.0 is 0.75, 0.5 of pixel_dimensions 2064x2752
probe: touch at 1032.0, 2064.0 is 0.5, 0.75 of pixel_dimensions 2064x2752
iPad Pro 13-inch (M5), landscape:
probe: usedpiscale=false highdpi=true Window.dpi_scale=1.0 Window.native_dpi_scale=2.0 Graphics.dpi_scale=1.0 Graphics.dimensions=[2752, 2064] Graphics.pixel_dimensions=[2752, 2064] Window.safe_area=[0, 64, 2752, 1960]
probe: touch at 688.0, 516.0 is 0.25, 0.25 of pixel_dimensions 2752x2064
probe: touch at 2064.0, 1032.0 is 0.75, 0.5 of pixel_dimensions 2752x2064
iPhone 17 Pro, portrait:
probe: usedpiscale=false highdpi=true Window.dpi_scale=1.0 Window.native_dpi_scale=3.0 Graphics.dpi_scale=1.0 Graphics.dimensions=[1206, 2622] Graphics.pixel_dimensions=[1206, 2622] Window.safe_area=[0, 186, 1206, 2334]
probe: touch at 302.0, 656.0 is 0.25, 0.25 of pixel_dimensions 1206x2622
probe: touch at 905.0, 1311.0 is 0.75, 0.5 of pixel_dimensions 1206x2622
probe: touch at 603.0, 1967.0 is 0.5, 0.75 of pixel_dimensions 1206x2622
iPhone 17 Pro, landscape:
probe: usedpiscale=false highdpi=true Window.dpi_scale=1.0 Window.native_dpi_scale=3.0 Graphics.dpi_scale=1.0 Graphics.dimensions=[2622, 1206] Graphics.pixel_dimensions=[2622, 1206] Window.safe_area=[186, 0, 2250, 1146]
```

The same game with `usedpiscale` left true printed `graphics dimensions: [402, 874] pixels: [1206, 2622] dpi scale: 3.0` on the iPhone 17 Pro, and without `t.highdpi`, `graphics dimensions: [390, 844] pixels: [390, 844] dpi scale: 1.0` on the iPhone 16e.

## What no CI run proves

No Simulator signs, installs over a cable, reads a real accelerometer, or plays through a speaker. Whether the device build signs with your team, installs, runs at the device's frame rate, sounds right, and honours the silent switch is what you find out on a device, and what the results file asks.
