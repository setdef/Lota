<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Building a Game for iPhone, iPad, and Android

Phones and tablets are where many games are played, and a Lota game runs there on the same engine as on a desktop. But a phone runs no `lota run`, and `lota fuse` builds only for the computer it runs on. A phone app is a project in its maker's own tools, an Xcode project for iOS and iPadOS and a Gradle project for Android, which you build, sign, and submit as you would any other app.

[Fledge](https://github.com/setdef/Fledge) writes that project. It puts a Ruby of its own and your game in it, and compiles Lota's engine and extension for the phone while it does. This page takes your game folder through Fledge to an app on a Simulator, an emulator, and a device, and on to the files the App Store and Google Play take.

The phone route is experimental. Read [What has run, and what has not](#what-has-run-and-what-has-not) before you promise anyone a phone build: a game has run on a real iPad and iPhone, and nothing yet on a real Android phone or tablet.

## What you need

For both systems:

- A clone of Lota's repository with its submodules. Lota's gem does not carry LÖVE's sources, so the phone build compiles LÖVE's engine from the clone's `vendor/love`. Its `bundle install` brings Rice, whose headers the build reads.
- Ruby 4.0 and Bundler, Git, CMake 3.21 or newer, and Ninja (optional, but faster).
- Fledge v0.6.0, which your phone project's `Gemfile` names by its Git tag. Fledge downloads its Ruby runtime for each phone the first time it builds.

For iOS and iPadOS, a Mac with:

- Xcode, with its iOS platform installed, and its command line tools.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), which Fledge runs to make the Xcode project.
- An Apple Developer account, to run the app on a device or send it to the App Store.

For Android, on x86-64 Linux:

- A JDK, 17 or newer, and the Android SDK, with its `platform-tools` and `build-tools`.
- The Android NDK, 30.0.16248370: `sdkmanager "ndk;30.0.16248370"`. Set `ANDROID_NDK_ROOT` to it.
- `make` and a shell, which two of LÖVE's libraries build with, through their `configure` scripts.

Lota's own checks build Android on Ubuntu 24.04. Fledge also builds Android projects on a Mac and on Windows, but Lota's Android libraries have not been built there yet.

## What is prebuilt, and what you build

Today you build Lota for a phone from source, on your own computer:

- **Lota's engine and extension** compile while `fledge build` runs, for each iOS slice (device and Simulator) or Android ABI (`arm64-v8a` and `x86_64`), from your clone. Lota publishes no prebuilt phone libraries yet.
- **SDL3** you build once, from LÖVE's release, 3.4.10. For iOS, `rake ios:sdl3` builds it as static libraries; for Android, `rake android:deps` builds it as `libSDL3.so`, and Lota's Android host carries the same release's Java classes, which must match the library the app loads.
- **LÖVE's other libraries** for iOS are prebuilt: the static archives in `vendor/love-apple-dependencies`, which LÖVE's own project publishes, and Apple's frameworks. For Android, `rake android:deps` builds them from each release's source archive, pinned by its SHA-256: zlib, libogg, libvorbis, libtheora, FreeType, HarfBuzz, and libmodplug as static libraries, and OpenAL Soft as `libopenal.so`.
- **Ruby** is Fledge's prebuilt runtime for each phone, downloaded and checked against the SHA-256 Fledge pins.

Building takes a while. On GitHub's runners, `rake ios:sdl3` took about 2 minutes and `fledge build ios` about 9; `rake android:deps` took about 5 minutes, SDL included, `fledge build android` 8, and Gradle's three builds 2. You run `rake ios:sdl3` and `rake android:deps` once (`rake android:deps` skips the build when its recipe and the NDK have not changed), but each `fledge build` compiles the engine again, once for each slice or ABI.

## Build Lota's parts once

Clone Lota with its submodules, here into `~/Lota`, and install its bundle:

```sh
git clone --recurse-submodules https://github.com/setdef/Lota.git ~/Lota
cd ~/Lota
bundle install
```

The commands below run in `~/Lota`.

For iOS, build SDL3 into `tmp/ios/sdl3`:

```sh
bundle exec rake ios:sdl3
```

For Android, build LÖVE's libraries and SDL3 into `tmp/android/deps`:

```sh
export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/30.0.16248370"
bundle exec rake android:deps
```

Then make a folder of the files Lota's gem packages, which your phone project names as its `lota` gem. A gem named by its path carries its whole folder into the app, so name this folder, not the clone:

```sh
mkdir -p tmp/phone
gem build lota.gemspec --output tmp/phone/lota.gem
gem unpack tmp/phone/lota.gem --target tmp/phone
gem specification tmp/phone/lota.gem --ruby > tmp/phone/lota/lota.gemspec
```

Run these again after you pull a new version of Lota.

## Lay out the phone project

Fledge builds from a project folder that holds a program, a `Gemfile`, and a `fledge.yml`. Keep it beside your game, not inside it: everything in the project folder but the hosts goes into the app. Lay it out as `lota fuse` lays out its own, with your game in `game/` under its identity, here `MyGame`:

```
MyGame-phone/
  Gemfile
  fledge.yml
  main.rb
  game/MyGame/       a copy of your game folder: conf.rb, main.rb, assets
  host/ios/          Lota's iOS host
  host/android/      Lota's Android host, with SDL's Java classes
```

Copy the game and Lota's hosts in:

```sh
mkdir -p MyGame-phone/game
cp -R path/to/my_game MyGame-phone/game/MyGame
cp -R ~/Lota/tmp/phone/lota/ext/lota/phone/host MyGame-phone/host
```

`main.rb` starts the game as a shipped game starts, as the program `lota fuse` writes does:

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
gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.6.0", group: :development
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

`name` is the Xcode target's and the app's name: letters and digits. The identifier is the reverse-DNS name the App Store and Google Play know the app by, under a domain of yours in place of `example.com`; changing it later makes a new app. A game's `t.version` names the version of LÖVE it was written for, so the app's version is `fledge.yml`'s.

Then tell Bundler where Lota's clone and its builds are, and lock the `ruby` platform, which Fledge builds a phone's gems for:

```sh
cd MyGame-phone
bundle config set --local build.lota "--with-lota-source=$HOME/Lota --with-lota-sdl3=$HOME/Lota/tmp/ios/sdl3 --with-rice-dir=$(cd ~/Lota && bundle info rice --path)"
bundle lock --add-platform ruby
bundle install
```

For Android, name Android's libraries, SDL among them, instead:

```sh
bundle config set --local build.lota "--with-lota-source=$HOME/Lota --with-lota-android-deps=$HOME/Lota/tmp/android/deps --with-rice-dir=$(cd ~/Lota && bundle info rice --path)"
```

### The hosts

SDL owns a phone's screen and its main loop, so a Lota app starts through SDL's startup files rather than Fledge's. Fledge builds the app, and ships no SDL: it links the libraries Lota's build names and copies a host folder over the project it writes (`ios: host:` and `android: host:`). Lota provides both, the SDL build (`rake ios:sdl3`, `rake android:deps`) and the hosts, in its gem, in `ext/lota/phone/host`; Fledge's own SDL example served as a reference, and nothing here runs it. They are yours to change once copied:

- **iOS** (`host/ios`): `Host/main.m` runs the game's Ruby on the main thread inside `SDL_RunApp`, with a 64 MB stack, and sends what the game prints to the unified log under the app's identifier. `Host/Info.plist` hides the status bar, runs at the screen's own size, turns to every orientation an iPad has and to portrait and both landscapes on an iPhone, reads a mouse or trackpad, and sets the audio session to `ambient`, which mixes with other apps' audio and which the silent switch mutes (`LotaAudioSessionCategory`: `ambient`, `soloAmbient`, or `playback`). The name under the icon is the target's; set `CFBundleDisplayName` for another. In the iPadOS 26.2 Simulator a game whose window is not fullscreen still showed the status bar; `t.window.fullscreen = true` hides it there, as it hides it for a LÖVE game on iOS, whose status bar LÖVE leaves to SDL, and SDL hides only for a fullscreen or borderless window. One departure from LÖVE: SDL shows the accelerometer as a joystick on iOS, and the host turns that off (`SDL_ACCELEROMETER_AS_JOYSTICK=0`), since an early Lota crashed reading that joystick; read the accelerometer through `Lota::Sensor`.
- **Android** (`host/android`): `MainActivity.java` is SDL's Activity. It loads SDL, OpenAL Soft, Ruby, and the app's extensions, runs the game's Ruby on a thread with a 64 MB stack, and has the methods LÖVE's engine calls on it, as LÖVE's own Android app has them. `AndroidManifest.xml` asks for OpenGL ES 3.0, vibration, and a full screen without a title bar.

SDL turns the screen to suit the game's window: a window wider than it is tall, such as the default 800 by 600, puts a phone in landscape, and one taller than wide in portrait. Either way the window takes the whole screen, at the size the phone gives it, so read `Lota::Graphics.dimensions` rather than assuming the size `conf.rb` asked for.

Android's Back reaches the game as `Lota.keypressed(:escape, :acback)`, and then SDL closes the app, as in LÖVE: the game gets `Lota.quit`, as on a desktop whose window closes. A game that decides what Back does adds this inside `<application>` in its `host/android/src/main/AndroidManifest.xml`, and the host also keeps Android 13 and newer from closing the app with predictive back:

```xml
<meta-data android:name="SDL_ENV.SDL_ANDROID_TRAP_BACK_BUTTON" android:value="1" />
```

## iPhone and iPad

`fledge build ios` writes the Xcode project, `dist/MyGame-ios`, with Ruby and Lota for both the device and the Simulator:

```sh
bundle exec fledge build ios
open dist/MyGame-ios/MyGame.xcodeproj
```

In Xcode, choose a Simulator and press Run. For a device, choose your team under Signing & Capabilities, connect the device, turn on its Developer Mode, and press Run.

From the command line, build for a device connected by cable, with your team, then install and launch it with `devicectl`:

```sh
xcodebuild -project MyGame.xcodeproj -scheme MyGame -configuration Debug -destination generic/platform=iOS \
  -derivedDataPath build DEVELOPMENT_TEAM=YOURTEAMID -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device DEVICE build/Build/Products/Debug-iphoneos/MyGame.app
xcrun devicectl device process launch --device DEVICE com.example.MyGame
```

What stood in the way the first time a game went onto an iPad and an iPhone this way:

- **Developer Mode is off.** Turn it on in Settings, Privacy & Security, Developer Mode, and let the device restart.
- **No signing certificate.** A team has none until the first build with `-allowProvisioningUpdates`, which makes one.
- **The device is trusted but not paired.** `devicectl manage pair` failed with a transport error; unplugging the cable and plugging it in again fixed it.
- **A free Personal Team has limits.** It signs at most 3 apps on a device and 10 App IDs a week, and its profile expires after about 7 days. The first launch also needs Settings, General, VPN & Device Management, and trusting the developer.
- **Xcode must know the device's iOS.** An older Xcode cannot install on a newer iOS.
- **Keep `OS_ACTIVITY_DT_MODE` out of the scheme's environment.** With it set, the host leaves the game's output on its own streams, so the unified log gets none of it.

From the command line, build for the Simulator and run it there:

```sh
cd dist/MyGame-ios
xcodebuild -project MyGame.xcodeproj -scheme MyGame -configuration Debug -sdk iphonesimulator -derivedDataPath build build
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/MyGame.app
xcrun simctl launch booted com.example.MyGame
xcrun simctl spawn booted log show --last 5m --predicate 'subsystem == "com.example.MyGame"'
```

The last line shows what the game printed.

For the App Store, archive the app with your team, then export it as an IPA:

```sh
xcodebuild archive -project MyGame.xcodeproj -scheme MyGame -destination generic/platform=iOS \
  -archivePath build/MyGame.xcarchive DEVELOPMENT_TEAM=YOURTEAMID -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/MyGame.xcarchive -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

`ExportOptions.plist` names the method, `app-store-connect` for the App Store or `release-testing` for devices you register, and your `teamID`; Xcode's Organizer writes one when you export there once. Or archive from Xcode (Product, then Archive) and distribute from the Organizer.

### Or let your game's CI build the Xcode project

If your game is in a GitHub repository, Lota's iOS kit workflow takes the steps above on GitHub's macOS runners, with the same host, and hands you the Xcode project as a zip, checked in iPhone and iPad Simulators in portrait and landscape: you need only a Mac with Xcode to open, sign, and run it. Your repository calls Lota's workflow by a release's tag; no release carries it yet, so until one does, name the commit of Lota's `trunk` that holds it. [The iOS kit](../contributors/ios-kit.md) has the call, its inputs, and what it checks. Unpack the zip with `ditto -x -k`, which keeps its symbolic links.

## Android

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

For Google Play, build the release App Bundle, and a release APK for anywhere else. Gradle leaves both unsigned; sign them with your own key, which `keytool` makes once:

```sh
./gradlew assembleRelease bundleRelease
keytool -genkeypair -keystore release.jks -alias release -keyalg RSA -keysize 4096 -validity 10000
jarsigner -keystore release.jks build/outputs/bundle/release/*.aab release
zipalign -f -P 16 4 build/outputs/apk/release/*-unsigned.apk MyGame-aligned.apk
apksigner sign --ks release.jks --out MyGame.apk MyGame-aligned.apk
```

`zipalign` and `apksigner` are in the SDK's `build-tools`. Upload the `.aab` to Google Play, which signs what it delivers with its own key once you enroll in Play App Signing; keep `release.jks` as your upload key. Or name the key in a `signingConfigs` block of `build.gradle`.

## Licences and notices

An app carries the notices of everything in it. Fledge writes its own runtime's in the app's `notices/`. Lota's gem folder goes into the app whole, with Lota's licence, the AGPL-3.0-or-later, so whoever you give the app to is owed its source and Lota's, as with a desktop app.

Lota writes the rest, the notices of LÖVE's engine and the libraries a phone build links, into the phone project's `NOTICES.txt`, which goes into the app's `app/` folder, as `lota fuse` writes a desktop app's. Run it in the clone, before `fledge build`, and again after you pull a new version of Lota:

```sh
bundle exec rake ios:notices[$HOME/MyGame-phone]
bundle exec rake android:notices[$HOME/MyGame-phone]
```

The file names Lota and each library, with its version, licences, and notices of copyright, and ends with the text of every licence it names. It comes from the clone's record of who wrote what, `ext/lota/licenses.rb`. FreeType's licence also asks that the app's documentation credit the FreeType Team, in words the file quotes; put them there too.

OpenAL Soft is under the GNU Library General Public License, version 2 or later, which lets a player replace it with a build of their own:

- **Android** links it as `libopenal.so`, a shared library apart from Lota's `libfledgeext.so`, as LÖVE's Android app does. Its source must go with the app, so `rake android:notices` also copies its release's archive, the one `rake android:deps` builds from, into the project's `sources/` folder, downloading it if it has to and checking its SHA-256, and the notices say where it is in the app.
- **iOS** plays sound through Apple's OpenAL framework, as LÖVE's iOS build does, so no LGPL code is in an iOS app.

## What has run, and what has not

Lota's `phones.yml` workflow takes this page's commands on Lota's own sample game, `test/games/phone`, on GitHub's runners:

- iOS, with Xcode 26.3 and XcodeGen 2.46.0 on macOS 15: the project builds for the Simulator, and for devices, Debug and Release, with signing off, and archives with signing off. The game runs in an iPhone 17 Pro and an iPad Pro 13-inch (M5) Simulator of iOS 26.2: it draws on Metal at the screen's own pixels (2622 by 1206 on the iPhone, in landscape), plays its tone, saves a file, finds graphics from another thread refused, quits after its 12 seconds, about 1,600 frames, and Ruby exits with status 0. Each line it prints reaches the log as it prints it, which Fledge v0.5.1 brought.
- Android, with the NDK 30.0.16248370 and Java 21 on Ubuntu 24.04: the project builds a debug APK, a release APK, and an App Bundle for `arm64-v8a` and `x86_64`, and the release APK and bundle sign with a key made for the run. The debug APK runs on an `x86_64` emulator of Android 16 (API 36): the game draws with OpenGL ES 3.0 through the emulator's software renderer, plays its tone through OpenSL ES, saves a file, takes a tap as a touch, finds graphics from another thread refused, quits, and Ruby exits with status 0; Back reaches it as `:escape` with the scancode `:acback`, and the game then quits.

On real devices, outside Lota's CI: a game's own build took this route from a clone of Lota at v0.1.3, with `rake ios:sdl3`, the same `build.lota` options, Fledge v0.5.1, and host files of the game's own, and installed it from a Mac by cable with `xcodebuild` (a Personal Team, `-allowProvisioningUpdates`) and `devicectl`, on an iPad Pro 12.9-inch (6th generation) with iPadOS 26.7.1 and an iPhone 13 mini with iOS 18.7.8. On both the game ran fullscreen with no status bar, in portrait and both landscapes; taps landed under the finger; sound played, and the silent switch muted it; tilting moved the accelerometer, which the Simulator has none of; and on the iPad a Bluetooth Xbox controller worked. On the iPhone 13 mini a thin column of the wrong colour showed at the right edge in landscape. A game at a display scale that is not a whole number (the iPhone 12 mini and 13 mini report 2.88) that keeps the default stencil, or depth, or MSAA, gets undrawn right-hand columns there on Metal: LÖVE's Metal backend makes the backbuffer's stencil and depth texture from the window's size in units times a scale it reads from the height (`src/modules/graphics/metal/Graphics.mm`, about lines 500 to 531), 2336 pixels where the drawable is 2338, and the render pass stops at the narrower. That is confirmed in the iPhone 13 mini Simulator (iOS 26.1); the check on the physical phone is pending. If a game uses none of them, set `t.window.stencil = false`, `t.window.depth = false`, and `t.window.msaa = 0`.

Not yet tried:

- Any real Android phone or tablet. The `arm64-v8a` build, which most Android phones use, has been built and never run, since no free runner boots an arm64 emulator.
- The device commands above as Lota's own CI would run them, and an iPad or iPhone with Lota's own hosts rather than a game's.
- Signing with a paid Apple team, exporting an IPA, TestFlight, App Review, and Google Play's review.
- Building Android on a Mac or on Windows.
- A game whose own `Gemfile` names other gems; this page's project asks for Lota and Fledge alone.
- Android's opt-in to handle Back, which an earlier experiment tried on the same emulator and this workflow does not.
- Restarting: a phone cannot restart a game by `exec`, so `Lota::Event.restart` ends it as a quit does.
- On Android, a real speaker, a real accelerometer, and the frame rate on a device.

Fledge's phone runtimes have no JIT (iOS gives an app no memory it may write code into and run, and Ruby builds none for Android; Fledge's ADR 011), so a game's Ruby runs slower on a phone than on a desktop with YJIT.
