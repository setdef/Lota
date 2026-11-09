<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Lota

[![CI](https://github.com/setdef/Lota/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/Lota/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/setdef/Lota)](https://github.com/setdef/Lota/releases) [![License](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FLota%2Ftrunk%2Flota.gemspec&search=spec%5C.license%20%3D%20%22(.*)%22&replace=%241&label=License&color=a2c93e)](https://spdx.org/licenses/AGPL-3.0-or-later.html) [![Ruby](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsetdef%2FLota%2Ftrunk%2Flota.gemspec&search=spec%5C.required_ruby_version%20%3D%20%22(.*)%22&replace=%241&label=Ruby&logo=ruby&color=a2c93e)](#compatibility) [![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-a2c93e)](#compatibility) [![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

## Introduction

**Lota** is a Ruby gem for making 2D games. It builds a modified version of the C++ engine that [LÖVE](https://love2d.org) games run on, and runs your game's Ruby on it instead of Lua. You get LÖVE's renderer, shaders, audio, and Box2D physics, and you write your game as plain Ruby methods.

Lota is an independent project. It is not made, endorsed, or supported by the LÖVE Development Team.

Lota is for Rubyists who want to make a 2D game in Ruby. If you have worked through a LÖVE tutorial, you already know Lota's modules and functions: they keep LÖVE's names, and a few fixed rules turn each Lua call into Ruby. `love.graphics.rectangle("fill", 10, 10, 50, 50)` becomes `Lota::Graphics.rectangle(:fill, 10, 10, 50, 50)`. A game you write in Lota behaves as the same game written for LÖVE, because both run the same engine code. On every change, Lota's CI runs three published LÖVE games on macOS and Linux in LÖVE and their Ruby translations in Lota, and compares every frame.

The name comes from the Lota Bowl, a classic Indian magic trick: the magician empties a brass vessel, and it fills itself again, as often as it is poured out. A game loop does the same, every frame.

### Compared with other ways to make a game in Ruby

- **[Gosu](https://www.libgosu.org/)** and **[Ruby2D](https://www.ruby2d.com/)** are Ruby gems with APIs of their own. Lota uses LÖVE's API, so LÖVE's wiki, tutorials, and example games apply once you translate the calls.
- **[DragonRuby Game Toolkit](https://dragonruby.org/)** has free and paid tiers, ships its own Ruby runtime, and exports games to the web, desktops, and (on its Pro tier) phones. Lota runs on the Ruby 4.0 you install, with your usual gems. Its gems are for desktops; a phone build is experimental, and compiles from source.
- **[LÖVE](https://love2d.org)** itself runs games written in Lua. Lota runs the same engine with Ruby in place of Lua.

## A first game

A Lota game is a folder. This one has two files, 20 lines in all. It slides a square across the window and quits when you press Escape.

```ruby
# conf.rb
def Lota.conf(t)
  t.window.title = "Hello, Lota"
end
```

```ruby
# main.rb
def Lota.load
  @x = 0
  puts "window #{Lota::Graphics.dimensions.join('x')}"
end

def Lota.update(dt)
  @x = (@x + 200 * dt) % Lota::Graphics.width
end

def Lota.draw
  Lota::Graphics.print("Hello from Ruby. Press Escape to quit.", 40, 40)
  Lota::Graphics.rectangle(:fill, @x, 280, 40, 40)
end

def Lota.keypressed(key)
  Lota::Event.quit if key == :escape
end
```

Run it from the game's folder:

```console
$ lota run
window 800x600
```

An 800 by 600 window opens, titled "Hello, Lota", with the text in the top left and a white square moving to the right. It wraps around at the edge. Escape closes the window and ends the program.

From here, [Images, sound, input, and saving](#images-sound-input-and-saving) builds a slightly larger game, and [Coming from LÖVE](#coming-from-löve) shows how to read a LÖVE tutorial as Lota code.

## Compatibility

| Platform | Gem platform | Status |
| --- | --- | --- |
| macOS 15 or newer on Apple Silicon | `arm64-darwin` | Released |
| Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36, and later) on x86_64 | `x86_64-linux-gnu` | Released |
| The same Linux on arm64 | `aarch64-linux-gnu` | Released |
| Windows on x64, with [RubyInstaller](https://rubyinstaller.org/)'s Ruby | `x64-mingw-ucrt` | Released |
| Windows on ARM64, with RubyInstaller's Ruby | `aarch64-mingw-ucrt` | Released |
| iPhone, iPad, and Android | none | Experimental, built from source |

- Lota needs Ruby 4.0 (4.0.1 or newer).
- On Linux, a game needs an X11 or Wayland desktop with OpenGL, as a LÖVE game does. CI runs the Linux tests on X11.
- On Windows, CI runs Lota's tests, Lövetest's among them, on Mesa's software OpenGL, as LÖVE's own CI does, installs the gem and runs a game from it, and runs apps that `lota fuse` built. GitHub's Windows runners have no GPU and no audio device, so those checks happen on a PC instead: a game has been played on a Windows PC, and Lövetest passes on an NVIDIA RTX 4090 with both Vulkan and OpenGL.
- Intel Macs and Linux with musl, such as Alpine, have no gem yet. On those, RubyGems picks Lota's source gem, which stops at install and says so.
- Phones and tablets have no gem yet. A game builds for them with [Fledge](https://github.com/setdef/Fledge) and a clone of Lota, or for iPhone and iPad from your game's CI: [Building a game for iPhone, iPad, and Android](doc/guide/phones.md) has both routes. Games have run in the iOS Simulator, on Android emulators, on real iPads and iPhones, and on one Android phone.

Lota binds every module of LÖVE's. Its threads are Ruby Ractors, which Ruby 4.0 calls experimental: a thread's code runs in a Ractor of its own, and a value it receives through a channel arrives frozen. A few functions are not bound yet, and a game that calls one stops with a `NoMethodError`. The [changelog](CHANGELOG.md) lists what each release added.

## Installation

Lota is not on RubyGems.org. Each [GitHub release](https://github.com/setdef/Lota/releases) carries a precompiled gem for each platform and a `SHA256SUMS` file. The gem carries LÖVE's engine and the libraries it uses, so installing it compiles nothing.

Download the gem for your platform from the newest release, check it, and install it. For 0.3.0:

```sh
version=0.3.0
platform=arm64-darwin   # or x86_64-linux-gnu, or aarch64-linux-gnu
curl -LO "https://github.com/setdef/Lota/releases/download/v$version/lota-$version-$platform.gem"
curl -LO "https://github.com/setdef/Lota/releases/download/v$version/SHA256SUMS"
shasum -a 256 --check --ignore-missing SHA256SUMS
gem install --local "lota-$version-$platform.gem"
lota --version
```

The last line prints `Lota 0.3.0`.

On Windows, download `lota-0.3.0-x64-mingw-ucrt.gem` (or `lota-0.3.0-aarch64-mingw-ucrt.gem` on ARM64) from the release page and run `gem install --local` on it, with RubyInstaller's Ruby.

If your game has a `Gemfile`, put the gem in the game's `vendor/cache` folder instead, ask for the version, and install from there. Add a gem for each platform you work on; Bundler locks every platform it finds a gem for.

```ruby
# Gemfile
source "https://rubygems.org"

gem "lota", "0.3.0"
```

```sh
bundle install --local
bundle exec lota run
```

## Usage

### The game folder

`lota run` runs the game in the current folder, and `lota run path/to/game` runs the one in that folder. Arguments after the folder go to your `Lota.load`.

- **`main.rb`** holds your game. It defines callbacks as methods on `Lota`.
- **`conf.rb`** is optional. It defines `Lota.conf(t)`, which Lota calls before it opens the window. Set the window's size and title there (`t.window.width = 1280`), name your save folder (`t.identity = "asteroids"`), or turn modules off (`t.modules.physics = false`). The settings keep LÖVE's names, so `conf.lua` from a tutorial translates line for line.
- **Other Ruby files** sit beside `main.rb`. The game's folder is on `$LOAD_PATH`, so `require "player"` loads `player.rb`.
- **Assets** such as images, fonts, and sounds go anywhere in the folder. Lota reads a file name relative to the game's folder, wherever you ran `lota run` from.

### Callbacks

Every callback is optional. Define the ones you need:

| Callback | When Lota calls it |
| --- | --- |
| `Lota.load(arguments)` | Once, after `main.rb` loads |
| `Lota.update(dt)` | Every frame, with the seconds since the last frame |
| `Lota.draw` | Every frame, after `update`, on a window cleared to the background color |
| `Lota.keypressed(key, scancode, isrepeat)` | When a key goes down, with the key as a Symbol, such as `:escape` |
| `Lota.mousepressed(x, y, button)` | When a mouse button goes down |
| `Lota.resize(width, height)` | When the window changes size |
| `Lota.quit` | When the game is about to quit; return `true` to keep it running |

The rest of LÖVE's callbacks work the same way, under LÖVE's names. Lota passes a callback only as many arguments as it declares, so `def Lota.keypressed(key)` receives the key alone.

### Images, sound, input, and saving

Most games need the same few things beyond a rectangle. With an image at `images/ship.png` and a sound at `sounds/laser.wav` in the game folder, this `main.rb` draws a ship, moves it with the arrow keys, fires on a click, and remembers how many shots you fired, from one run to the next:

```ruby
# main.rb
def Lota.load
  @ship = Lota::Graphics::Image.new("images/ship.png")
  @laser = Lota::Audio::Source.new("sounds/laser.wav", :static)
  Lota::Graphics.font = Lota::Graphics::Font.new(24)
  @x, @y = 400, 300
  shots, = Lota::Filesystem.read("shots.txt")   # nil when there is no such file
  @shots = shots.to_i
end

def Lota.update(dt)
  @x -= 200 * dt if Lota::Keyboard.down?(:left)
  @x += 200 * dt if Lota::Keyboard.down?(:right)
end

def Lota.draw
  Lota::Graphics.draw(@ship, @x, @y)
  Lota::Graphics.color = 1, 1, 0
  Lota::Graphics.print("Shots: #{@shots}", 20, 20)
  Lota::Graphics.color = 1, 1, 1
end

def Lota.mousepressed(x, y, button)
  return unless button == 1

  @laser.clone.play
  @shots += 1
end

def Lota.quit
  Lota::Filesystem.write("shots.txt", @shots.to_s)
  false
end
```

Three things in it differ from Lua.

- **A function that can return several values always returns an Array**, on success and on failure. `Lota::Filesystem.read` returns `[contents, size]` or `[nil, message]`, so `shots, = ...` takes the first. An Array is always true in Ruby, even `[nil, message]`, so `if Lota::Filesystem.write("shots.txt", data)` is always true. Where Lua writes `if love.filesystem.write(...) then`, write `.first`:

  ```ruby
  unless Lota::Filesystem.write("shots.txt", @shots.to_s).first
    warn "could not save the shots"
  end
  ```

- **Setters are writers.** `love.graphics.setColor(1, 1, 0)` is `Lota::Graphics.color = 1, 1, 0`, and getters drop `get`: `love.graphics.getWidth()` is `Lota::Graphics.width`.
- **LÖVE's names for things are Symbols.** `"left"`, `"static"`, and `"escape"` are `:left`, `:static`, and `:escape`.

For a whole game to read, Lota's repository holds Ruby translations of three published LÖVE games, which its CI runs frame for frame against the originals: the [arkanoid tutorial](test/games/arkanoid), [Gravity-Wars](test/games/gravity_wars), and [KleleAtoms](test/games/klele_atoms).

### Coming from LÖVE

If you have a LÖVE tutorial or game in front of you, these rules cover most of its lines:

| LÖVE (Lua) | Lota (Ruby) |
| --- | --- |
| `function love.update(dt)` | `def Lota.update(dt)` |
| `love.graphics.rectangle("fill", x, y, w, h)` | `Lota::Graphics.rectangle(:fill, x, y, w, h)` |
| `love.graphics.newImage("ship.png")` | `Lota::Graphics::Image.new("ship.png")` |
| `love.graphics.getWidth()` | `Lota::Graphics.width` |
| `love.window.setTitle("Game")` | `Lota::Window.title = "Game"` |
| `love.mouse.setPosition(x, y)` | `Lota::Mouse.position = x, y` |
| `love.keyboard.isDown("space")` | `Lota::Keyboard.down?(:space)` |
| `x, y = love.mouse.getPosition()` | `x, y = Lota::Mouse.position` |
| `love.window.setMode(800, 600, {resizable = true})` | `Lota::Window.set_mode(800, 600, resizable: true)` |
| `love.graphics.push()` ... `love.graphics.pop()` | `Lota::Graphics.push { ... }` |
| `body:applyForce(fx, fy)` | `body.apply_force(fx, fy)` |

`lota` works anywhere as another name for `Lota`, so `lota.graphics.rectangle(...)` and `def lota.update(dt)` read as a tutorial's `love.graphics` and `function love.update(dt)` do. [Translating LÖVE code](doc/guide/translating.md) has every rule, and the places where Ruby and Lua differ.

### Saved files

LÖVE's filesystem reads from your game's folder and writes to a save folder. Lota names the save folder after your game's folder, or after `t.identity` if `conf.rb` sets one:

| System | Save folder |
| --- | --- |
| macOS | `~/Library/Application Support/Lota/<identity>` |
| Linux | `$XDG_DATA_HOME/lota/<identity>`, or `~/.local/share/lota/<identity>` |
| Windows | `%APPDATA%\Lota\<identity>` |

LÖVE's `love` program saves in the same places, in a `LOVE` folder (`love` on Linux) instead of `Lota`. A game built with `lota fuse` (below) saves where a fused LÖVE game saves, in `<identity>` directly under the same folder, without `Lota`: `%APPDATA%\<identity>` on Windows, for one. `Lota::Filesystem.save_directory` returns the path.

### Errors

When your game raises an error, Lota prints it with its Ruby backtrace and shows LÖVE's error screen in the game's window: the error and backtrace in white on blue. Press Ctrl+C to copy them. Press Escape or close the window to quit, with exit status 1. To show something else, define `Lota.errorhandler(error)`, as a LÖVE game defines `love.errorhandler`.

### Sharing a game

`lota fuse` builds your game into an app that a player runs without Ruby, as LÖVE fuses a game into an executable of its own. It hands the game to [Fledge](https://github.com/setdef/Fledge), which packages a Ruby program with a Ruby of its own. Run it in the game's folder, or name the folder:

```console
$ lota fuse path/to/game --identifier com.example.SampleGame
dist/Sample Game-x64-mingw-ucrt.zip
dist/Sample Game-x64-mingw-ucrt-setup.exe
Built the app for x64-mingw-ucrt only. Run lota fuse on each platform you ship for.
```

Fledge builds for the computer it runs on, so build each platform's app on that platform: on a Mac for macOS, on Windows for Windows, on Linux for Linux. A player gets:

| Platform | What `lota fuse` writes in `dist` |
| --- | --- |
| macOS | `NAME.app`, in a `.tar.gz` and a `.dmg` |
| Windows | `NAME.exe` and what it needs, in a `.zip`, and a `-setup.exe` that installs it without an administrator |
| Linux | A folder with `NAME` and a desktop entry, in a `.tar.gz`, and an AppImage (glibc 2.39 or newer: Ubuntu 24.04, Debian 13) |

The app's name is `conf.rb`'s `t.window.title`, or else `t.title`, or else the game folder's name. It saves under `t.identity`, or under the game folder's name, as `lota run` does. `lota fuse` writes the project it builds from in `dist/fuse-project`, and the game goes in it under `game/<identity>`. Fledge runs from a Gemfile of its own beside it, in `dist/fuse-tools`, so it is none of the app's gems.

To fuse a game, you need:

- Lota's gem for your platform, installed from the release as above. `lota fuse` puts that very gem file in the app, unless your game's `vendor/cache` holds it.
- Ruby 4.0, which the app gets a copy of: on Windows, [RubyInstaller](https://rubyinstaller.org/)'s Ruby 4.0 for x64 or ARM64. Its MSYS2 tools are needed only for a gem that compiles (below).
- Git, and the network: Fledge is not on RubyGems.org, so Bundler fetches it from GitHub, and Fledge downloads its runtime for your platform the first time. On Windows, install [Git for Windows](https://git-scm.com/download/win); on a Mac, `xcode-select --install` installs Git. Fledge carries what it builds installers with, NSIS among them.

The options:

- `--identifier ID` is the reverse-DNS name macOS and Windows know the app by, such as `com.example.SampleGame`. Without it the app gets `com.example.<identity>`, a placeholder: replace it before you ship.
- `--app-version VERSION` is the app's version, such as `1.0.0`; without it, Fledge's `0.0.0`. A game's `t.version` names the version of LÖVE it was written for, so it never becomes the app's.
- `--icon PATH` gives the app the icon files at `PATH` in the game's folder, without their extension, as Fledge takes them: `--icon icons/icon` for `icons/icon.icns` (macOS), `icons/icon.ico` (Windows), and `icons/icon-16.png` to `icons/icon-512.png` (Linux). Without it the app has no icon of its own.
- `--sign IDENTITY` signs the app, as Fledge's `--sign` does: a signing identity from your keychain on macOS, a certificate's SHA-1 thumbprint on Windows. Unsigned, Gatekeeper and SmartScreen warn the people who download it.
- `--sign-command COMMAND` signs a Windows app with a command of your own instead, as Fledge's `--sign-command` does, for a certificate kept in a cloud or hardware service: Fledge runs `COMMAND` through `cmd.exe` for each program and library, the uninstaller, and the setup program, with the file's path in place of `%1`, or after `COMMAND` if it has no `%1`. Given neither option on Windows, Fledge takes the command from `FLEDGE_SIGN_COMMAND`.
- `--notarize PROFILE` has Apple notarize the macOS app that `--sign` signed with a Developer ID Application identity, and staples Apple's ticket to it, as Fledge's `--notarize` does, with the credentials that `xcrun notarytool store-credentials PROFILE` stored in your keychain. It waits for Apple, usually minutes.
- `--exclude PATTERN` leaves paths out of the app; see below. Give it as often as you like.
- `--out DIR` writes to `DIR` instead of `dist`.
- `LOTA_FLEDGE_REF` names another tag or commit of Fledge to build with.

`--sign` and `--sign-command` together, or `--notarize` without `--sign`, stop `lota fuse` before it writes anything. Fledge refuses `--sign-command` on any system but Windows, `--notarize` on any but macOS or with the ad hoc identity `-`, and an app Apple will not notarize, and `lota fuse` stops after Fledge says why.

The app holds your game's folder as it is, but for `.git`, `.bundle`, `vendor/bundle`, and `vendor/cache`, which it always leaves out. To leave out more, such as a server's code, your tests, and your docs, give `--exclude` a pattern for each:

```console
$ lota fuse path/to/game --exclude server --exclude 'test/**' --exclude doc
dist/Sample Game-x64-mingw-ucrt.zip
Left out 3 paths of the game: doc, server, test/a_test.rb
Built the app for x64-mingw-ucrt only. Run lota fuse on each platform you ship for.
```

A pattern is a glob relative to the game's folder, matched as Ruby's `File.fnmatch` does with `FNM_PATHNAME`, `FNM_EXTGLOB`, and `FNM_DOTMATCH`. So `*` stays within a folder, `**/` crosses folders (`**/*.psd`), `{a,b}` picks one of two (`*.{psd,xcf}`), and `*` matches dotfiles too, because someone who writes `assets/*` means the `.DS_Store` in it. Quote a pattern with a star, so your shell hands it to `lota fuse` as written. A path that matches is left out whole: `server` leaves out the folder `server` at the top of the game, with everything in it, but not `lib/server`. A pattern that ends in a slash (`doc/`) matches folders only. `test/**` is everything in `test`, as `fnmatch` reads it, so it leaves an empty `test` folder. `lota fuse` reads no file of patterns, and it prints the paths it left out. A pattern that matches nothing is reported, but does not stop the build. One that would leave out `conf.rb` or `main.rb`, which the game needs to start, stops it before it writes anything, as every error of `lota fuse` does, with exit status 1.

If your game has a `Gemfile`, the app ships the gems its `Gemfile.lock` locks, at the versions it locks, but for the `development` and `test` groups. `lota fuse` builds from your Gemfile and lockfile, and adds Lota if your Gemfile does not ask for it. Before it builds, it checks that:

- a `Gemfile.lock` is beside the `Gemfile`. Run `bundle install` in the game's folder to write one.
- the lockfile locks the platform you build on. Run `bundle lock --add-platform x64-mingw-ucrt` (or your platform) in the game's folder; a gem that only `vendor/cache` holds, such as Lota, needs that platform's `.gem` file there first.
- the lockfile locks this version of Lota, if it locks Lota at all.

Gems come from where your lockfile says: RubyGems.org, Git, a folder inside the game, or the game's `vendor/cache`, whose gems for other platforms stay out of the app. Bundler only locks them; it installs none. Fledge fetches each gem the app ships and checks it against your lockfile's checksum. A shipped gem with a C extension and no build for your platform compiles once, on your computer, for the app's Ruby. A gem in the `development` or `test` group never compiles, so a game whose shipped gems are all pure Ruby or precompiled fuses without a C compiler. Any other needs one: on macOS, Xcode's command line tools (`xcode-select --install`); on Linux, a C compiler and `make` (`sudo apt install build-essential` on Debian and Ubuntu); on Windows, RubyInstaller's MSYS2 tools (`ridk install`). Without one, `lota fuse` stops after the compiler's output names the gem that failed, and says what to install. An extension compiles for the computer it compiles on, which is one more reason to build each platform's app on that platform.

Every app carries a notices file, `app/NOTICES.txt`, in the folder beside the app's program (in `NAME.app/Contents/Resources` on macOS). It states Lota's license, AGPL-3.0-or-later, and names each library Lota's gem for that platform carries, compiled into Lota's extension or beside it, with its version where it is known, its licenses, and its notices of copyright. It gives FreeType's credit in the words FreeType's license asks for, says where OpenAL Soft's source archive is in the app, and ends with the text of each license it names. `lota fuse` writes it on every build from the very gem the app ships, and stops on a Lota gem that does not carry what it needs. Fledge's own `notices/NOTICES.txt`, beside it, covers Ruby and the rest of the runtime.

Your other gems go into the app whole, with the license files their packages hold, whatever their licenses. What those licenses ask of you when you give the app to people is yours to honor, as with any Ruby program you ship: `bundle licenses` lists the license each gem declares, and a gem whose package leaves out its license text, which a license such as MIT asks you to keep with every copy, needs it added to the notices you ship.

A fused game restarts as LÖVE's does: `Lota::Event.restart` ends it, and the app's program starts it again with the same arguments, with `Lota.restart` holding the value, as `lota run` and `bundle exec lota run` do.

What a fused game does not do yet: `lota fuse` builds no phone app; [the phone guide](doc/guide/phones.md) builds one with Fledge directly, or with the iOS kit from your game's CI. On Windows the app opens no console, so what the game prints goes nowhere, and Ruby's YJIT is not in RubyInstaller's Ruby, so a Windows app runs without it; elsewhere the app turns YJIT on.

## Documentation

| Resource | Description |
| --- | --- |
| `ri Lota::Graphics.rectangle` | The API reference for any class or method, installed with the gem. Most entries name the LÖVE function they translate |
| [`lib/`](lib) | The same reference in the source, for reading on GitHub. Lota does not host its API docs online yet |
| [Translating LÖVE code](doc/guide/translating.md) | Every naming rule, and how Lota differs from Lua where Ruby has no equivalent |
| [Building a game for iPhone, iPad, and Android](doc/guide/phones.md) | The experimental phone build: the iOS kit your game's CI can call, the build by hand for iOS and Android, devices, the App Store and Google Play, the notices an app carries, and what has run |
| [LÖVE's wiki](https://love2d.org/wiki/Main_Page) | What each function does. Look up a Lota method under its LÖVE name |
| [CHANGELOG](CHANGELOG.md) | What changed in each release |
| [Agent skill](skills/lota-gamedev/SKILL.md) | A skill for coding agents that write Lota games: where the API is documented, what differs on phones, and how to test and ship. It is in the installed gem (`gem contents lota \| grep SKILL.md`), and `gh skill install setdef/Lota lota-gamedev` or `npx skills add setdef/Lota` installs it from a release |
| [Releases](https://github.com/setdef/Lota/releases) | The gems and their checksums |

## Reporting problems

Lota's GitHub repository does not take issues yet.

## Contributing

To build Lota from source, run its checks, or change it, start with [doc/contributors/development.md](doc/contributors/development.md).

## Copyright & License

Lota is copyright 2026, setdef. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](https://github.com/love2d/love/blob/main/license.txt), © LÖVE Development Team.

Some parts of this program, and of its precompiled gems, come from other sources under their own licenses, and their copyright belongs to their owners. Each file says which, by the [REUSE Specification – Version 3.3](https://reuse.software/spec-3.3/). Each precompiled gem's `REUSE.toml` records them for the compiled extension, which holds LÖVE's engine and the libraries LÖVE bundles, and for each framework, or on Linux and Windows each shared library, the gem carries, and its `LICENSES` folder holds their texts.

The precompiled gem carries FreeType, which it uses under the [FreeType License](ext/lota/licenses/LICENSE-FTL.txt). As that license asks of a binary distribution: the software is based in part of the work of the FreeType Team.

Lota is an independent project. It is not made, endorsed, or supported by the LÖVE Development Team. It builds a modified version of LÖVE's engine.

## How Lota is made

I use three words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code or prose I requested, an agent built with little or no review from me, in the style of a "dark factory."

Lota's design decisions and its agent instructions are wrought. Everything else, the code, tests, build, this README, and the guide, is requested, and the CI gates stand in for review: sanitizers, clang-tidy, the package checks, the delivery jobs that install each gem on a clean runner, and the parity tests against LÖVE. Each commit says which it holds in a `Provenance:` trailer. Under [declare-ai.org](https://declare-ai.org/1.0.0/creative.html), this is creative assistance.
