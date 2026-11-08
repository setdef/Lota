# @DISPLAY_NAME@ for iPhone and iPad: the Xcode project

This folder is an Xcode project that builds @DISPLAY_NAME@ as an app for iPhone and iPad: one app, one binary, for both. The project is yours. Open it, sign it with your own Apple ID or team, put the game on your own devices, and change it as you would any Xcode project. It needs no Lota, no Fledge, no Ruby, and no XcodeGen on your Mac: everything it builds from is already inside.

**If you are playtesting, answer the questions in `@RESULTS_FILE@` and send that file back.** It sits next to this README and is the only thing to send. Steps 1 to 5 below get the game onto your device in about half an hour with a free Apple ID. Everything after them is there if you want it.

## What is in this folder

- `@APP_NAME@.xcodeproj`, the project, already generated. Open it.
- `Host/`, the app's own code and settings: `main.m` starts SDL and runs the game's Ruby program, and `Info.plist` holds the app's name, orientations, and status bar settings.
- `FledgeRuby.xcframework`, the Ruby runtime, for devices and for the Simulator.
- `FledgeExtensions.xcframework`, Lota's engine and SDL3, compiled for devices and for the Simulator.
- `fledge/`, the game itself (`fledge/app`) and the configuration that starts it.
- `project.yml`, what XcodeGen generated the project from. You never need it; regenerating would undo your signing settings.
- `BUILD-INFO.txt`, which names the commits, tools, and CI run that made this kit.
- `@RESULTS_FILE@`, the playtest questions.

The game is @GAME_REPOSITORY@ at @GAME_REF@ (commit @GAME_SHA@), folder `@GAME_PATH@`, built with Lota at commit @LOTA_SHA@ and Fledge @FLEDGE_REF@. Its program is @PROGRAM@. Its icon is @ICON@.

## What CI checked, and what it did not

The workflow that made this kit (Lota's `.github/workflows/ios-kit.yml`, run @RUN_ID@, @RUN_URL@) unpacked it on a second, fresh Mac with no Lota, Fledge, XcodeGen, or Ruby gems, and built it there with `xcodebuild`: for the Simulator, and with signing turned off for devices, Debug and Release. It then ran the Simulator build in iPad and iPhone Simulators, several launches each in portrait and in landscape, and kept the screenshots and the app's log. A UI test tapped the screen and turned the Simulator from portrait to landscape and back.

No one has run this build on a physical device. The device build compiled and linked, unsigned; whether it signs, installs, runs, sounds right, and feels right on your iPhone or iPad is what you find out.

## What the Mac needs

- **@XCODE@ or newer.** The libraries inside were compiled by that Xcode, so an older Xcode may fail to link them. Xcode runs an app only on a device whose iOS it knows; if your device is newer, Xcode offers to download its support next to the run destination.
- **An Apple ID.** A free one works.
- **A cable** for the iPhone or iPad.

## 1. Download and unpack

If this README is already in an unpacked folder, open `@APP_NAME@.xcodeproj` beside it and go on to step 2. Otherwise, from the Terminal, with the run's number from the workflow's page:

```sh
mkdir -p ~/@APP_NAME@Kit && cd ~/@APP_NAME@Kit
gh run download @RUN_ID@ -R @RUN_REPOSITORY@ -n ios-kit
shasum -a 256 -c SHA256SUMS
ditto -x -k @APP_NAME@-ios.zip .
open @APP_NAME@-ios/@APP_NAME@.xcodeproj
```

Or, in the browser, open the run, download `ios-kit` under Artifacts, and double-click the zips in Finder. Finder's Archive Utility and `ditto` keep the zip's symbolic links, which the frameworks inside rely on. Avoid tools that turn links into copies or drop them.

## 2. Sign it with your Apple ID

1. **Add your Apple ID.** Xcode > Settings > Apple Accounts (Accounts in older Xcode), press +, and sign in. Xcode lists a team named "YOUR NAME (Personal Team)", or your company's team if you are in the Apple Developer Program.
2. **Choose the team.** In the project navigator select @APP_NAME@ (the blue project icon), then the @APP_NAME@ target under Targets, then Signing & Capabilities. Turn on "Automatically manage signing" and choose your team.
3. **Choose the bundle identifier.** It is `@IDENTIFIER@`. If Xcode says it "is not available" or "cannot be registered", another team holds it: change it to one under a domain of your own (`com.example.@APP_NAME@`, with your domain for `example.com`), and Xcode tries again. Nothing else in the project depends on it.

A free Personal Team signs for 7 days at a time, for at most 3 apps on a device and 10 App IDs a week. A paid membership signs for a year and can ship to TestFlight and the App Store.

## 3. Get the device ready

1. **Pair it.** Plug the iPhone or iPad in, unlock it, and tap Trust on "Trust This Computer?". Enter its passcode.
2. **Turn on Developer Mode.** On the device: Settings > Privacy & Security > Developer Mode, at the bottom. The switch appears only after the device has been paired with a Mac running Xcode. Turn it on, let the device restart, then tap Turn On and enter the passcode.

## 4. Check the scheme

Product > Scheme > Edit Scheme, then Run > Arguments. Under Environment Variables there should be no `OS_ACTIVITY_DT_MODE`, with any value, `NO` and empty included. If Xcode added it, select it and press −. With that variable set, the system copies every log entry to standard error, so the host program leaves the game's output on its own streams, and Xcode's console shows it there instead of the device's log.

You may add the game's own settings here, as environment variables, if it reads any.

## 5. Run

Choose the device as the run destination in the toolbar (the menu next to the scheme's name) and press Run (⌘R). Xcode builds the Debug configuration, signs, installs, and launches.

The first launch may stop at "Untrusted Developer". On the device open Settings > General > VPN & Device Management, tap your Apple ID under Developer App, tap Trust, and press Run again.

Once installed, @DISPLAY_NAME@ is on the Home Screen. It runs without the Mac until its signature expires.

## What you should see

@DISPLAY_NAME@ fills the screen @STATUS_BAR@ (on an iPad, a game whose window is not fullscreen, `t.window.fullscreen`, may still show it). On an iPhone it turns to @IPHONE_ORIENTATIONS@; on an iPad to @IPAD_ORIENTATIONS@. Its sound category is @AUDIO@.

The host makes two choices LÖVE does not. It hides SDL's accelerometer joystick (`SDL_ACCELEROMETER_AS_JOYSTICK=0` in `Host/main.m`), as a guard, since reading that joystick crashed an early Lota in the Simulator. A game reads the accelerometer through `Lota::Sensor`, and a paired controller is still a joystick. Set `SDL_ACCELEROMETER_AS_JOYSTICK` = `1` in the scheme to bring it back. And its `LotaApplication` (`Host/main.m`, named by `NSPrincipalClass` in `Info.plist`) reports the window scene's orientation where iOS 27 no longer reports one to SDL, which would otherwise give a game launched in landscape a portrait window. Keep both if you change the host.

## When something goes wrong

What to send back, by where it fails:

- **The build or signing fails in Xcode.** The red messages in the Issue navigator (⌘5), copied as text, and the Report navigator's build log (⌘9, the newest Build, Export).
- **The app starts and then closes, or freezes.** The log, below, and the crash report: Window > Devices and Simulators, select the device, Open Recent Logs (or View Device Logs), and the newest `@APP_NAME@` entry; on the device itself, Settings > Privacy & Security > Analytics & Improvements > Analytics Data, the newest `@APP_NAME@-….ips`, which the Share button sends.
- **It runs but looks or sounds wrong.** A screenshot, which way the device was turned, and the log.

### Reading the log

The game's output goes to the device's unified log under the subsystem `@IDENTIFIER@` (or your identifier), category `ruby`; the host's last line, "@DISPLAY_NAME@ exited with status N", is under category `app`. While Xcode runs the app, its console (⇧⌘C) shows these lines. Without Xcode, open Console.app on the Mac, select the device in the sidebar, press Start, and type `subsystem:@IDENTIFIER@` in the search field. Play until the problem shows, select the lines, and copy them.

### The game's saved files

The game saves in the app's container, under Library/Application Support. To copy them to the Mac: Window > Devices and Simulators, select the device, select @DISPLAY_NAME@ under Installed Apps, click the … (gear) button, and Download Container. Show the package's contents in Finder.

## Making it your own

The project is a normal Xcode project. Change the name under the icon in Build Settings > User-Defined > `APP_DISPLAY_NAME`, the orientations and status bar in `Host/Info.plist` or the target's General tab, the icon in `Host/Assets.xcassets`, and the audio session's category in `Info.plist`'s `LotaAudioSessionCategory` (`ambient`, `soloAmbient`, or `playback`). Archive it (Product > Archive) with a paid team to send it to TestFlight.

## After 7 days

With a free Personal Team the app stops launching when its profile expires. Plug the device in, open the same `@APP_NAME@.xcodeproj`, and press Run again: Xcode makes a new profile and installs over the old app, which keeps the game's saved files. Deleting the app from the device deletes them.

To try a newer build of the game, download the newer kit and do steps 1, 2, and 5 again. Keep the same bundle identifier, so it installs over the old app and keeps one of the device's 3 app slots.
