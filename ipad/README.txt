
# Playtesting Dot Popper on an iPad

You have a Mac with Xcode, an Apple ID, and an iPad on a cable. This page takes Dot Popper from a CI artifact to that iPad in about half an hour, with a free Apple ID and no Lota, Fledge, Ruby, or XcodeGen on the Mac.

The kit is an Xcode project that the "iPad kit" workflow (`.github/workflows/ipad-kit.yml`, on `experiment/ipad-*` branches) generates with `fledge build ios` (Fledge 0.4.0, SDL's iOS host) from a Dot Popper commit (trunk by default) and Lota's checkout. Its program, `bin/ipad_kit`, runs Dot Popper's own `bin/dot_popper`; it adds a diagnostic log line only when CI sets `DOT_POPPER_KIT_PROBE=1`. The project is already generated, so it opens in Xcode as it is. It holds everything it builds from: the Ruby runtime (`FledgeRuby.xcframework`), Lota's engine and SDL3 compiled for the iPad and the Simulator (`FledgeExtensions.xcframework`), and the game (`fledge/app`).

## What CI proved, and what it did not

The workflow unpacks the zip on a second, fresh runner, with no Lota, Fledge, XcodeGen, or bundle, and builds it there with `xcodebuild`: for the Simulator, and for devices with signing turned off. It then runs the Simulator build in iPad Simulators with the game's autoplay bot, and keeps screenshots and the app's log. `BUILD-INFO.txt` in the zip names the run, the commits, and the Xcode and XcodeGen versions.

For Dot Popper 0.5.1 that meant: Xcode 26.3 built the unpacked project for the Simulator and, unsigned, for devices (Debug and Release), and the game ran in iOS 26.2 Simulators of an iPad Pro 13-inch (M5), an iPad (A16), and an iPad mini (A17 Pro). The bot played to the end and the app reported exit status 0, with all four shaders, the fonts, the particles, the physics pile, and the save folder working. A separate UI test tapped the screen and turned the Simulator from portrait to landscape and back: taps started rounds, and the field and the score pill relaid themselves for each orientation.

No one has run this app on a physical iPad. The device build compiled and linked, unsigned; whether it signs, installs, runs, and sounds right on the iPad is what this playtest finds out.

## What the Mac needs

- **Xcode 26.3 or newer** (CI built and checked the kit with Xcode 26.3, 17C529, and the iOS 26.2 SDK; `BUILD-INFO.txt` names the version for each kit). The libraries inside were compiled by that Xcode, so an older Xcode may fail to link them. Xcode runs an app only on an iPad whose iPadOS it knows; if the iPad is newer, Xcode offers to download its support next to the run destination.
- **Nothing else.** The zip holds `DotPopper.xcodeproj`, already generated. CI's check runner had no XcodeGen, no Ruby gems, and no Lota or Fledge, and built the project anyway. XcodeGen (2.x, the version in `BUILD-INFO.txt`) is needed only to regenerate the project from `project.yml`, which this playtest never does; regenerating would undo your signing settings.

## 1. Download and unpack

From the Terminal, with the run's number from the workflow's page:

```sh
mkdir -p ~/DotPopperKit && cd ~/DotPopperKit
gh run download RUN -R setdef/Lota -n dot-popper-ios-project
shasum -a 256 -c SHA256SUMS
ditto -x -k DotPopper-ios.zip .
open DotPopper-ios/DotPopper.xcodeproj
```

Or, in the browser, open the run, download `dot-popper-ios-project` under Artifacts, and double-click the zips in Finder. Finder's Archive Utility and `ditto` keep the zip's symbolic links, which the frameworks inside rely on. Avoid tools that turn links into copies or drop them.

## 2. Sign it with your Personal Team

1. **Sign in.** Xcode > Settings > Accounts (Apple Accounts in newer Xcode), press +, and add your Apple ID. Xcode lists a team named "YOUR NAME (Personal Team)".
2. **Choose the team.** In the project navigator select DotPopper (the blue project icon), then the DotPopper target under Targets, then Signing & Capabilities. Turn on "Automatically manage signing" and choose your Personal Team.
3. **Keep the identifier, or change it.** The Bundle Identifier is `com.kerricklong.DotPopper`. If Xcode says it "is not available" or "cannot be registered", someone else holds it: change it to one of your own, such as `com.kerricklong.DotPopper.playtest`, and Xcode tries again. Nothing else depends on it.

A free Personal Team signs for 7 days at a time, for at most 3 apps on the iPad and 10 App IDs a week (Apple, "Choosing a membership").

## 3. Get the iPad ready

1. **Pair it.** Plug the iPad in, unlock it, and tap Trust on "Trust This Computer?". Enter the iPad's passcode.
2. **Turn on Developer Mode.** On the iPad: Settings > Privacy & Security > Developer Mode (at the bottom, under Security). The switch appears only after the iPad has been paired with a Mac running Xcode. Turn it on, restart the iPad, and after the restart tap Turn On and enter the passcode.

## 4. Check the scheme

Product > Scheme > Edit Scheme, then Run > Arguments. Under Environment Variables there should be no `OS_ACTIVITY_DT_MODE`, with any value, `NO` and empty included. If Xcode added it, select it and press −. With that variable set, the system copies every log entry to standard error, and the Ruby runtime of Fledge 0.4.0 sends standard error back to the log, so the game would freeze in a loop of its own output. The kit's host program checks for the variable and, when it is set, leaves the game's output on its own streams instead, but the scheme is the place to keep it out.

You may add Dot Popper's own settings here, such as `DOT_POPPER_CALM` = `1` (no screen shake). Leave `DOT_POPPER_AUTOPLAY` out for a playtest: it makes a bot play.

## 5. Run

Choose the iPad as the run destination in the toolbar (the menu next to the scheme's name) and press Run (⌘R). Xcode builds the Debug configuration for the iPad, signs, installs, and launches.

The first launch may stop at "Untrusted Developer". On the iPad open Settings > General > VPN & Device Management, tap your Apple ID under Developer App, tap Trust, and press Run again.

Once installed, Dot Popper is on the Home Screen. It runs without the Mac, until the 7 days are up.

## What you should see

Dot Popper fills the screen, with no status bar, in portrait and in landscape: turn the iPad and the field rebuilds. In the iPad Simulator it looked like this: the score and time in a pill at the top, orange glowing dots about a fingertip wide, purple rings where dots were popped, sparkles and "+1 +1s" on each pop, and at the end "Time!", the score, and the dots piling up at the bottom. The title screen comes first; tap to play, and tap the dots. Sound is synthesized when the game loads and mixes with other apps' audio, and the silent switch mutes it.

One known workaround is built in. The kit's host program turns off SDL's accelerometer joystick (`SDL_ACCELEROMETER_AS_JOYSTICK=0` in `Host/main.m`), because reading joysticks through Lota crashed the game in the Simulator; Dot Popper 0.5.1 also leaves joysticks alone on iOS. A game controller paired with the iPad does nothing in this build.

## When something goes wrong

What to send back, by where it fails:

- **The build or signing fails in Xcode.** The red messages in the Issue navigator (⌘5), copied as text (select them, ⌘C), and the Report navigator's build log (⌘9, the newest Build, Export).
- **The app starts and then closes, or freezes.** The log, below, and the crash report: Window > Devices and Simulators, select the iPad, Open Recent Logs (or View Device Logs), and the newest `DotPopper` entry; on the iPad itself, Settings > Privacy & Security > Analytics & Improvements > Analytics Data, the newest `DotPopper-….ips`, which the Share button sends.
- **It runs but looks or sounds wrong.** A screenshot (the iPad's top and volume-up buttons together), which way the iPad was turned, and the log.

### Reading the log

The game's output goes to the iPad's unified log under the subsystem `com.kerricklong.DotPopper` (or your identifier), category `ruby`; the host's last line, "Dot Popper exited with status N", is under category `app`. While Xcode runs the app, its console (⇧⌘C) shows these lines. Without Xcode, open Console.app on the Mac, select the iPad in the sidebar, press Start, and type `subsystem:com.kerricklong.DotPopper` in the search field. Then play until the problem shows, select the lines, and copy them.

A healthy start prints, among others:

```
Dot Popper: a dot's radius is 50 points, about 8 mm
Dot Popper: each round is logged in …/Library/Application Support/dot_popper/rounds.csv
```

Any line that starts `Dot Popper: could not`, `Dot Popper: drawing without`, or `Dot Popper: playing without` is the game saying something failed and it carried on. Send those.

### The game's saved files

Dot Popper saves its best scores and `rounds.csv`, a line for each round played, in the app's Library/Application Support/dot_popper folder. To copy them to the Mac: Window > Devices and Simulators, select the iPad, select Dot Popper under Installed Apps, click the … (gear) button, and Download Container. Show the package's contents in Finder.

## After 7 days

The app stops launching when its profile expires. Plug the iPad in, open the same `DotPopper.xcodeproj`, and press Run again: Xcode makes a new profile and installs over the old app. Installing over it keeps the saved scores; deleting the app from the iPad deletes them.

To try a newer build of the game, download the newer kit and do steps 1, 2, and 5 again. Keep the same Bundle Identifier, so it installs over the old app and keeps one of the iPad's 3 app slots.
