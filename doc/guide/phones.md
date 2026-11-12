<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Building a Game for iPhone, iPad, and Android

Phones and tablets are where many games are played, and a Lota game runs there on the same engine as on a desktop. But a phone runs no `lota run`, and `lota fuse` builds only for the computer it runs on. A phone app is a project in its maker's own tools, an Xcode project for iOS and iPadOS and a Gradle project for Android, which you build, sign, and submit as you would any other app.

[Fledge](https://github.com/setdef/Fledge) writes that project. It puts a Ruby of its own and your game in it, and compiles Lota's engine for the phone while it does. This page takes your game from its folder to an app in a Simulator, an emulator, and on a device, and on to the files the App Store and Google Play take.

The phone route is experimental. Games have run on real iPads and iPhones and on one Android phone; [What has run](#what-has-run) says exactly what, so read it before you promise anyone a phone build.

## Two ways to build

- **The iOS kit.** If your game lives in a GitHub repository, your game's CI can call Lota's iOS kit workflow. It builds everything on GitHub's macOS runners, checks the app in iPhone and iPad Simulators, and hands you a zipped Xcode project. To open it, you need a Mac with Xcode and an Apple ID, and no Ruby, Lota, or Fledge.
- **By hand.** You build Lota's parts from a clone of Lota, lay out a Fledge project, and run `fledge build`. This is the only route to Android, and the one to take when you change Lota or its hosts.

Both routes use the same host, the startup files that run your game on the phone, so a game behaves the same either way.

## The iOS kit

### Call it from your game's CI

Add this workflow to your game's repository. It calls Lota's as a reusable workflow, so your CI copies no scripts. Name a release of Lota by its tag, such as `v0.3.0`, in both `uses` and `lota_ref`; the two must match.

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
    uses: setdef/Lota/.github/workflows/ios-kit.yml@v0.3.0
    with:
      lota_ref: v0.3.0
      game_repository: ${{ github.repository }}
      game_ref: ${{ github.sha }}
      display_name: "Sample Game"
      identifier: com.example.SampleGame
      icon: icons/icon-*.png
      smoke_env: SAMPLE_GAME_QUIT_AFTER=12
```

The jobs run on your repository's macOS runners, and the kit lands on your run. Your run's token checks the game out, so your repository may be private.

### Its inputs

Only `lota_ref` and `game_repository` are required.

- **`lota_ref`** is the tag your `uses` line names.
- **`game_repository`** is the game's repository as `OWNER/NAME`, usually `${{ github.repository }}`.
- **`game_ref`** is a tag, branch, or commit; empty takes the default branch.
- **`game_path`** is the game's folder in the repository, the one with `main.rb`; `.` by default.
- **`display_name`** is the name under the icon. It may hold spaces and any Unicode. Empty takes the repository's name.
- **`app_name`** is the Xcode target's and the program's name: ASCII letters and digits, starting with a letter. Empty derives it from `display_name`, so "Sample Game" becomes `SampleGame`.
- **`identifier`** is the bundle identifier. Empty gives `com.example.APP_NAME`, a placeholder you change when you sign.
- **`program`** is the Ruby program the app runs, relative to `game_path`. Empty writes the program `lota fuse` writes, which boots your game as a shipped game. Name your own to boot the game another way.
- **`icon`** is a folder, a glob such as `icons/icon-*.png`, or a PNG, relative to the repository's root. The workflow takes the 1024 by 1024 PNG, from which Xcode makes every other size. Without one the app gets a plain generated icon, and the run warns you.
- **`orientations`** reads like `iphone: portrait landscape; ipad: all`, which is the default. The words are `portrait`, `upside-down`, `landscape-left`, `landscape-right`, `landscape` (both), and `all`. A list without `iphone:` or `ipad:` sets both.
- **`audio_category`** is the audio session's category: `ambient` (the default, which mixes with other apps' audio and which the silent switch mutes), `solo-ambient`, `playback`, or `default`.
- **`hide_status_bar`** is true by default. On an iPad, a game whose window is not fullscreen still shows the status bar; set `t.window.fullscreen = true` to cover the whole screen.
- **`kit_questions`** names a text file of playtest questions. A line such as `Does the paddle follow your finger? | y/n` becomes a numbered question with blanks for an answer and a note. The types are `y/n`, `yes/no`, `yes/no + text`, `rating` (1 to 5), `choice: a/b/c`, and `text`. The kit carries the questions as `APP_NAME-results.txt`, with the game's and Lota's commits already filled in. Empty uses a short generic questionnaire.
- **`artifact_name`** names the kit's artifact, `ios-kit` by default. Give each call its own name if one workflow calls the kit twice.
- **`project_run`** checks the kit an earlier run built instead of building a new one.

These inputs shape only CI's own Simulator runs, never the app you get:

- **`smoke_env`** passes `NAME=VALUE` pairs, separated by spaces, to the game in each normal launch. Give your game a setting that makes it play itself and quit, and pass it here, so CI sees more than a title screen.
- **`smoke_expect`** is a Ruby regular expression the game's output must match.
- **`smoke_seconds`** is how long a normal launch may run, 40 by default.
- **`touch_env`** adds pairs to `smoke_env` for the launch the touch test taps, such as one that keeps the game running longer.
- **`extra_launches`** adds portrait launches, separated by `;`, each with pairs of its own, such as a replay of a saved game.

A launch passes when the app neither crashes nor prints `[BUG]`, and either exits with status 0 or is still running when its time is up. So a game that quits by itself must quit with 0.

### What CI checks

The workflow builds the kit, then unpacks it on a second Mac with no Lota, Fledge, or XcodeGen, and builds it there for the Simulator and, unsigned, for devices. It runs the game in several iPad and iPhone Simulators in portrait, then in landscape, and taps the screen and turns it on two of them, keeping screenshots and the game's output. No Simulator signs, installs over a cable, reads a real accelerometer, or plays through a speaker; that is what the playtest questions are for.

### Open the kit

When the run is green, download its `ios-kit` artifact:

```sh
gh run download RUN -R OWNER/NAME -n ios-kit
```

It holds `APP_NAME-ios.zip`, `kit.json` (what the run made of your inputs), and `SHA256SUMS`. Unpack the zip with `ditto -x -k` or Finder, which keep its symbolic links; the frameworks inside rely on them. Then follow the `README.txt` inside: add your Apple ID in Xcode, choose your team, set the bundle identifier, pair the device by cable, turn on Developer Mode, trust the developer, and press Run.

The zip holds the Xcode project, already generated, with one target for iPhone and iPad; the host, `Host/main.m` and `Host/Info.plist`; Ruby and Lota's engine, built for devices and the Simulator; your game in `fledge/`; and `BUILD-INFO.txt`, which names every commit and tool that made it. The project is yours to brand, sign, and change.

## Build by hand

### What you need

For both systems:

- A clone of Lota's repository with its submodules. Lota's gem does not carry LÖVE's sources, so the phone build compiles LÖVE's engine from the clone's `vendor/love`, unless the gem pins a prebuilt engine ([Prebuilt engines](#prebuilt-engines) says when).
- Ruby 4.1 with Bundler, Git, CMake 3.21 or newer, and Ninja, all on your `PATH`. Until Ruby 4.1.0 is released, that Ruby is a preview, such as 4.1.0-preview1.
- Fledge v0.12.0, the Fledge `lota fuse` builds with. Your phone project's `Gemfile` names it by its Git tag. Fledge downloads its Ruby for each phone the first time it builds.

For iOS and iPadOS, a Mac with:

- Xcode, with its iOS platform and its command line tools.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), which Fledge runs to make the Xcode project.
- An Apple ID, to run the app on a device, or an Apple Developer account, to send it to the App Store.

For Android, on x86-64 Linux:

- A JDK, 17 or newer.
- The Android SDK with its `platform-tools`, and the Android NDK 30.0.16248370.
- `make` and a shell, which two of LÖVE's libraries build with.

The SDK starts as its command-line tools. Download "Command line tools only" for Linux from [Android Studio's download page](https://developer.android.com/studio), and unpack the zip's `cmdline-tools` folder as `cmdline-tools/latest` in a folder for the SDK, such as `~/Android/Sdk`. Then accept the licences and install the rest:

```sh
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
yes | sdkmanager --licenses
sdkmanager "platform-tools" "ndk;30.0.16248370"
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/30.0.16248370"
```

On x86-64 Linux with no Android SDK at all, `bundle exec rake android:ndk` in Lota's clone installs the same NDK into `tmp/android/ndk`, checking the download's SHA-256, and prints the `ANDROID_NDK_ROOT` to export; that is enough to build Lota's parts and run `fledge build android`, though not Gradle.

Gradle installs Android's platform 36 and its `build-tools` the first time it builds the app, so that first build needs the network. Lota's own checks build Android on Ubuntu 24.04; Fledge also builds Android on a Mac and on Windows, but Lota's Android libraries have not been built there.

### Build Lota's parts once

No release of Lota publishes prebuilt phone engines yet, so you build them. Clone Lota, here into `~/Lota`, and install its bundle:

```sh
git clone --recurse-submodules https://github.com/setdef/Lota.git ~/Lota
cd ~/Lota
bundle install
```

For iOS, build SDL3 into `tmp/ios/sdl3`. LÖVE's other libraries for iOS come prebuilt, in `vendor/love-apple-dependencies`, beside Apple's frameworks.

```sh
bundle exec rake ios:sdl3
```

For Android, with `ANDROID_NDK_ROOT` set, build SDL3 and LÖVE's other libraries into `tmp/android/deps`. Each comes from its release's source archive, pinned by its SHA-256. The task skips the build when its recipe and the NDK have not changed.

```sh
bundle exec rake android:deps
```

Then make a folder of the files Lota's gem packages, which your phone project names as its `lota` gem. A gem named by its path carries its whole folder into the app, so name this folder, not the clone:

```sh
mkdir -p tmp/phone
gem build lota.gemspec --output tmp/phone/lota.gem
gem unpack tmp/phone/lota.gem --target tmp/phone
gem specification tmp/phone/lota.gem --ruby > tmp/phone/lota/lota.gemspec
```

Run these again after you pull a new version of Lota. Built from source, Lota's engine compiles each time `fledge build` runs, once for each iOS slice (device and Simulator) or Android ABI (`arm64-v8a` and `x86_64`), so a build takes several minutes.

### Prebuilt engines

LÖVE's engine and its libraries do not depend on Ruby, so Lota's CI builds them once for each iOS slice and Android ABI, and a release can publish them beside its gems. The gem's `ext/lota/phone/engines.txt` pins them: it names the release that published them and each one's checksum, so a clone between releases fetches the same engines as the release it names. When the gem pins them, its phone build fetches the engine for each slice or ABI from that release, checks its SHA-256, and keeps it in `~/.cache/lota/phone-engine` (or under `XDG_CACHE_HOME`), so `fledge build` compiles only Lota's extension, and needs none of LÖVE's sources, SDL3, or the libraries `rake android:deps` builds. Each prebuilt engine carries the same `NOTICES.txt` that `rake ios:notices` and `rake android:notices` write, and the Android ones carry OpenAL Soft's source.

`--with-lota-source=DIR` in `bundle config build.lota` asks for the engine built from source instead, as the steps here do, and is needed while the gem pins none; without it, a gem that pins none stops and says so. Two more options shape the fetch: `--with-lota-engine-url=URL` names a mirror of the release's assets, a web address or a `file://` folder, and `--with-lota-engine-cache=DIR` another folder to keep them in. Lota's extension is built against Ruby's ABI, so it still compiles in every phone build.

### Lay out the phone project

Fledge builds from a project folder that holds a program, a `Gemfile`, and a `fledge.yml`. Everything in it but the hosts goes into the app, so keep it beside your game, not inside it. Put your game in `game/` under its identity, here `MyGame`, as `lota fuse` does:

```
MyGame-phone/
  Gemfile
  fledge.yml
  main.rb
  game/MyGame/       a copy of your game folder: conf.rb, main.rb, assets
  host/ios/          Lota's iOS host
  host/android/      Lota's Android host
```

Copy the game and Lota's hosts in:

```sh
mkdir -p MyGame-phone/game
cp -R path/to/my_game MyGame-phone/game/MyGame
cp -R ~/Lota/tmp/phone/lota/ext/lota/phone/host MyGame-phone/host
```

`main.rb` boots the game as a shipped game, as the program `lota fuse` writes does:

```ruby
# frozen_string_literal: true

RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
require "lota"
exit Lota::Boot.new(File.join(__dir__, "game", "MyGame"), ARGV, fused: true).call
```

The `Gemfile` names Lota's folder and Fledge's tag:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gem "lota", path: "/Users/you/Lota/tmp/phone/lota"
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.12.0", group: :development
```

`fledge.yml` names the app, its identifier, its version, and the hosts:

```yaml
name: MyGame
identifier: com.example.MyGame
version: 1.0.0
ios:
  host: host/ios
android:
  host: host/android
```

`name` is the Xcode target's and the app's name, in letters and digits. The identifier is the reverse-DNS name the App Store and Google Play know the app by, under a domain of yours in place of `example.com`; changing it later makes a new app. The app's version comes from here, since a game's `t.version` names the version of LÖVE it was written for.

Last, tell Bundler where Lota's clone and its builds are, and lock the `ruby` platform, which Fledge builds a phone's gems for. Ask the clone's bundle for Rice's folder first, while you are still in `~/Lota`: in the phone project, `bundle info rice` finds nothing, and `fledge build` then stops with `RICE_DIR () holds no include/rice/rice.hpp`.

```sh
rice=$(bundle info rice --path)
cd MyGame-phone
bundle config set --local build.lota "--with-lota-source=$HOME/Lota --with-lota-sdl3=$HOME/Lota/tmp/ios/sdl3 --with-rice-dir=$rice"
bundle lock --add-platform ruby
bundle install
```

For Android, name Android's libraries instead:

```sh
bundle config set --local build.lota "--with-lota-source=$HOME/Lota --with-lota-android-deps=$HOME/Lota/tmp/android/deps --with-rice-dir=$rice"
```

### iPhone and iPad

`fledge build ios` writes the Xcode project, `dist/MyGame-ios`, with Ruby and Lota for both the device and the Simulator:

```sh
bundle exec fledge build ios
open dist/MyGame-ios/MyGame.xcodeproj
```

In Xcode, choose a Simulator and press Run. For a device, choose your team under Signing & Capabilities, connect the device, turn on its Developer Mode, and press Run.

From the command line, build for the Simulator, run the game there, and read what it printed:

```sh
cd dist/MyGame-ios
xcodebuild -project MyGame.xcodeproj -scheme MyGame -configuration Debug -sdk iphonesimulator -derivedDataPath build build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/MyGame.app
xcrun simctl launch booted com.example.MyGame
xcrun simctl spawn booted log show --last 5m --predicate 'subsystem == "com.example.MyGame"'
```

For a device connected by cable, build with your team, then install and launch with `devicectl`:

```sh
xcodebuild -project MyGame.xcodeproj -scheme MyGame -configuration Debug -destination generic/platform=iOS \
  -derivedDataPath build DEVELOPMENT_TEAM=YOURTEAMID -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device DEVICE build/Build/Products/Debug-iphoneos/MyGame.app
xcrun devicectl device process launch --device DEVICE com.example.MyGame
```

If the device refuses, check these first:

- **Developer Mode is off.** Turn it on in Settings, Privacy & Security, Developer Mode, and let the device restart.
- **There is no signing certificate.** A team has none until the first build with `-allowProvisioningUpdates` makes one.
- **The device is trusted but not paired.** If `devicectl manage pair` fails with a transport error, unplug the cable and plug it in again.
- **A free Personal Team has limits.** It signs at most 3 apps on a device and 10 App IDs a week, and its profile expires after about 7 days. The first launch also needs Settings, General, VPN & Device Management, and trusting the developer.
- **Xcode does not know the device's iOS.** An older Xcode cannot install on a newer iOS.
- **The game prints nothing to the log.** Keep `OS_ACTIVITY_DT_MODE` out of the scheme's environment. With it set, the host leaves the game's output on its own streams, so the unified log gets none of it.

For the App Store, archive the app with your team, then export it as an IPA:

```sh
xcodebuild archive -project MyGame.xcodeproj -scheme MyGame -destination generic/platform=iOS \
  -archivePath build/MyGame.xcarchive DEVELOPMENT_TEAM=YOURTEAMID -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/MyGame.xcarchive -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

`ExportOptions.plist` names the method, `app-store-connect` for the App Store or `release-testing` for devices you register, and your `teamID`. Xcode's Organizer writes one when you export there once. Or archive from Xcode (Product, then Archive) and distribute from the Organizer.

### Android

`fledge build android` writes the Gradle project, `dist/MyGame-android`, with Ruby and Lota for `arm64-v8a` and `x86_64`:

```sh
bundle exec fledge build android
cd dist/MyGame-android
./gradlew assembleDebug
```

The debug APK, in `build/outputs/apk/debug`, is signed with the Android SDK's debug key. Install it on an emulator or on a phone with USB debugging on, and read what the game prints:

```sh
adb install -r build/outputs/apk/debug/*.apk
adb shell am start -n com.example.MyGame/org.setdef.fledge.host.MainActivity
adb logcat
```

For Google Play, build the release App Bundle, and a release APK for anywhere else. Gradle leaves both unsigned, so sign them with your own key, which `keytool` makes once:

```sh
./gradlew assembleRelease bundleRelease
keytool -genkeypair -keystore release.jks -alias release -keyalg RSA -keysize 4096 -validity 10000
jarsigner -keystore release.jks build/outputs/bundle/release/*.aab release
zipalign -f -P 16 4 build/outputs/apk/release/*-unsigned.apk MyGame-aligned.apk
apksigner sign --ks release.jks --out MyGame.apk MyGame-aligned.apk
```

`zipalign` and `apksigner` are in the SDK's `build-tools`. Upload the `.aab` to Google Play, which signs what it delivers with its own key once you enroll in Play App Signing; keep `release.jks` as your upload key. Or name the key in a `signingConfigs` block of `build.gradle`.

## The hosts

SDL owns a phone's screen and its main loop, so a Lota app starts through SDL's startup files rather than Fledge's own. Lota's gem carries a host for each system in `ext/lota/phone/host`, and Fledge copies it over the project it writes. Once you copy a host into your project it is yours to change, but keep the parts this section marks.

**iOS** (`host/ios`). `Host/main.m` runs the game's Ruby on the main thread inside SDL, with a 64 MB stack, and sends what the game prints to the unified log under the app's identifier. `Host/Info.plist` hides the status bar, runs at the screen's own size, allows every orientation on an iPad and portrait and both landscapes on an iPhone, reads a mouse or trackpad, and sets the audio session to `ambient` (`LotaAudioSessionCategory`: `ambient`, `soloAmbient`, or `playback`). The name under the icon is the target's; set `CFBundleDisplayName` for another. The host departs from LÖVE's iOS app twice:

- SDL shows the accelerometer as a joystick on iOS, and the host turns that off (`SDL_ACCELEROMETER_AS_JOYSTICK=0`). Read the accelerometer through `Lota::Sensor`. A paired controller is still a joystick.
- On iOS 27, SDL gives a game launched in landscape a portrait window, cut off and black on one side, in LÖVE's own iOS app as well, because it reads the orientation from a place iOS 27 no longer fills (`doc/contributors/upstream/019.md`). The host's `LotaApplication`, named as `NSPrincipalClass` in `Info.plist`, answers with the window scene's orientation instead. Keep both.

**Android** (`host/android`). `MainActivity.java` is SDL's Activity. It loads SDL, OpenAL Soft, Ruby, and the app's extensions, runs the game's Ruby on a thread with a 64 MB stack, and has the methods LÖVE's engine calls on it. `AndroidManifest.xml` asks for OpenGL ES 3.0, vibration, and a full screen. The host departs from LÖVE's Android app twice:

- Android restarts an activity for any change of configuration its manifest does not list, and SDL then closes the app. LÖVE's app lists only a turn of the screen and a keyboard coming or going, so a change to dark mode, the font, the language, or the display size ends a LÖVE game. Lota's manifest also lists `uiMode`, `fontScale`, `fontWeightAdjustment`, `locale`, `layoutDirection`, `assetsPaths`, and `density` in `android:configChanges`, so the game keeps running, and hears dark mode as `Lota.themechanged` and the language as `Lota.localechanged`. Keep them when you change the manifest.
- When the game leaves the screen, SDL lets go of its window at once, and LÖVE's Vulkan renderer, still drawing a frame, then crashes, in LÖVE's own Android app as well (`doc/contributors/upstream/017.md`). The host waits, up to 2 seconds and usually a few milliseconds, until the game has paused. Keep `gamePaused` and `createSDLSurface` when you change the activity.

## Screens and input

SDL turns the screen to suit the game's window. A window wider than it is tall, such as the default 800 by 600, puts a phone in landscape, and one taller than wide puts it in portrait. Either way the window takes the whole screen at the size the phone gives it, so read `Lota::Graphics.dimensions` rather than assuming the size `conf.rb` asked for.

With `t.highdpi = true` a game draws at the screen's own pixels; without it, as in LÖVE, it draws at 1x. `t.window.usedpiscale` decides what units the game counts in. When it is true, the default, sizes, positions, and touches count in points: an iPhone 17 Pro in portrait is 402 by 874 at a DPI scale of 3. When it is false, they count in pixels, `Lota::Graphics.dimensions` equals `pixel_dimensions`, and a touch at a quarter of the screen's width reads a quarter of `pixel_dimensions`' width. `Lota::Window.safe_area` counts in the same units.

On an iPad, a game whose window is not fullscreen still shows the status bar over its top edge, as a LÖVE game does. Set `t.window.fullscreen = true` to cover it.

Android's Back reaches the game as `Lota.keypressed(:escape, :acback)`, and then SDL closes the app, as in LÖVE: the game gets `Lota.quit`, as on a desktop whose window closes. To decide what Back does yourself, add this inside `<application>` in `host/android/src/main/AndroidManifest.xml`; the host then also keeps Android 13 and newer from closing the app with predictive back:

```xml
<meta-data android:name="SDL_ENV.SDL_ANDROID_TRAP_BACK_BUTTON" android:value="1" />
```

A phone cannot restart a program in place, so `Lota::Event.restart` ends the game as a quit does.

## Sound files

On iOS and iPadOS, Lota decodes sound through Apple's Core Audio as well, as LÖVE's iOS build does, so `Lota::Sound::SoundData.new`, `Lota::Sound::Decoder.new`, and `Lota::Audio::Source.new` read AIFF, and AAC in an `.m4a` file, besides the WAV, Ogg Vorbis, FLAC, MP3, and tracker modules they read everywhere. Android and the desktops have no such decoder, so keep the sounds of a game for more than iOS in one of those other formats.

## The privacy manifest

An App Store listing wants a privacy manifest, `PrivacyInfo.xcprivacy`, that names each category of "required reason" API your app calls and why. Without the right entries, App Store Connect emails you about the upload.

`fledge build ios` writes `Host/PrivacyInfo.xcprivacy` with two entries: file timestamps (`NSPrivacyAccessedAPICategoryFileTimestamp`, reason `C617.1`) and system boot time (`NSPrivacyAccessedAPICategorySystemBootTime`, reason `35F9.1`). Lota's engine and SDL need no other category: their timers call `mach_absolute_time`, and their filesystems call `stat` on files inside the app's container. Three things change that list:

- **A `Host/PrivacyInfo.xcprivacy` in your host folder** replaces Fledge's whole, with no merging. Repeat both entries in it.
- **Showing file dates to the player**, from `Lota::Filesystem::Info#modtime` for example, adds `DDA9.1` to the file timestamp entry's reasons.
- **Opening files the player chose**, through document types in `Info.plist` or a file picker of your own, adds `3B52.1` to the same entry.

That list comes from reading the source of LÖVE, SDL, and Lota's host, and Lota's CI checks what the built app imports against it. No App Store upload has validated it yet. If App Store Connect names a category this section leaves out, add it to your manifest and tell Lota.

## Licences and notices

An app carries the notices of everything in it. Fledge writes its own runtime's in the app's `notices/`. Lota's gem goes into the app whole, with Lota's licence, the AGPL-3.0-or-later, so whoever you give the app to is owed its source and Lota's, as with a desktop app. Fledge is MIT-licensed, so its runtime adds no source for you to offer.

Lota writes the rest, the notices of LÖVE's engine and the libraries a phone build links, into the phone project's `NOTICES.txt`, which goes into the app's `app/` folder, as `lota fuse` writes a desktop app's. Run it in the clone before `fledge build`, and again after you pull a new version of Lota:

```sh
bundle exec rake ios:notices[$HOME/MyGame-phone]
bundle exec rake android:notices[$HOME/MyGame-phone]
```

The file names Lota and each library, with its version, licences, and copyright notices, and ends with the text of every licence it names. FreeType's licence also asks that the app's documentation credit the FreeType Team, in words the file quotes; put them there too.

OpenAL Soft is under the GNU Library General Public License, version 2 or later, which lets a player replace it with a build of their own:

- **Android** links it as `libopenal.so`, apart from Lota's `libfledgeext.so`, as LÖVE's Android app does. Its source must go with the app, so `rake android:notices` also copies its release's archive into the project's `sources/` folder, checking its SHA-256, and the notices say where it is in the app.
- **iOS** plays sound through Apple's OpenAL framework, as LÖVE's iOS build does, so no LGPL code is in an iOS app.

## What has run

On every push, Lota's CI takes this page's steps on a sample game:

- **iOS**, in an iPhone 17 Pro and an iPad Pro 13-inch (M5) Simulator. The project builds for the Simulator and, unsigned, for devices, Debug and Release, and archives. The game draws on Metal at the screen's own pixels, plays a tone, decodes an AIFF and an M4A sound through Core Audio, saves a file, finds graphics from another thread refused, and quits with status 0. The iOS kit's checks run its sample games in more Simulators, in portrait and landscape, with taps and turns.
- **Android**, on `x86_64` emulators of Android 16 and Android 13. The project builds a debug APK, a release APK, and an App Bundle, and the release builds sign. On Android 16 the game draws with OpenGL ES through the emulator's software renderer, plays its tone, saves a file, takes a tap, and quits with status 0, and Back reaches it as `:escape`. On Android 13 the same APK draws with Vulkan. On both, sent home, to the recent apps, and to a dark screen, it comes back each time and draws again.

On real devices, outside CI:

- A game's builds, with a lightly customised copy of Lota's iOS host, ran on an iPad Pro 12.9-inch (6th generation) with iPadOS 26, an iPhone 13 mini with iOS 18, and an iPhone 12 mini with iOS 27: fullscreen with no status bar, in portrait and both landscapes, with taps under the finger, sound that the silent switch mutes, the accelerometer, and, on the iPad, a Bluetooth game controller. On the iPhone 12 mini it went to the background and back, and Metal survived.
- Lota's own iOS host, unmodified, ran the phone check on an iPhone 12 mini with iOS 27: Metal on the A14 drew about 1,200 frames, and the check saved a file, played its tone, found graphics from another thread refused, and quit with status 0. The host's sample identifier has no provisioning profile, so the build was signed under the identifier of an existing team's app.
- An `arm64-v8a` build with Lota's own Android host ran on a OnePlus Nord N30 5G with Android 14 and an Adreno 619 GPU, on Vulkan, which LÖVE's engine chose there. It survived Home, the recent apps, a share sheet, and the screen turning off, each time in the same process and drawing again, and drew with vsync off.

### Known problems

On an iPhone 12 mini or 13 mini in landscape, a thin column at the right edge can show the wrong colour. These phones have a display scale that is not a whole number (2.88), and at such a scale LÖVE's Metal renderer makes the stencil, depth, and MSAA buffers two pixels narrower than the screen, so the last columns are never drawn (`doc/contributors/upstream/011.md`). A Simulator confirms it; a physical phone with the fix below has not been checked yet. If your game uses none of them, turn all three off:

```ruby
def Lota.conf(t)
  t.window.stencil = false
  t.window.depth = false
  t.window.msaa = 0
end
```

### Not yet tried

- Any other Android phone, and any Android tablet. No free runner boots an arm64 emulator, so the `arm64-v8a` build has run only on the one phone above.
- iOS 27 in a Simulator; CI's Simulators run iOS 26.
- Signing with a paid Apple team, exporting an IPA, TestFlight, App Review, and Google Play's review.
- Building Android on a Mac or on Windows.
- A game whose `Gemfile` names other gems.
- Android's opt-in to handle Back.
- On Android, a real speaker, a real accelerometer, and the frame rate on a device.

Fledge's phone runtimes have no JIT, since iOS gives an app no memory it may write code into and run, and Ruby builds none for Android. A game's Ruby therefore runs slower on a phone than on a desktop with YJIT, and each call into the engine costs several times what it costs on a desktop.
