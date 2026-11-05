<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
- **[DragonRuby Game Toolkit](https://dragonruby.org/)** has free and paid tiers, ships its own Ruby runtime, and exports games to the web, desktops, and (on its Pro tier) phones. Lota runs on the Ruby 4.0 you install, with your usual gems, and runs on desktops only so far.
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

## Compatibility

| Platform | Gem platform | Status |
| --- | --- | --- |
| macOS 15 or newer on Apple Silicon | `arm64-darwin` | Released |
| Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36, and later) on x86_64 | `x86_64-linux-gnu` | Released |
| The same Linux on arm64 | `aarch64-linux-gnu` | Released |
| Windows on x64, with [RubyInstaller](https://rubyinstaller.org/)'s Ruby | `x64-mingw-ucrt` | Released |
| Windows on ARM64, with RubyInstaller's Ruby | `aarch64-mingw-ucrt` | Released |

- Lota needs Ruby 4.0 (4.0.1 or newer).
- On Linux, a game needs an X11 or Wayland desktop with OpenGL, as a LÖVE game does. CI runs the Linux tests on X11.
- On Windows, CI installs the gem and runs a game that opens no window and plays a sound, and a manual workflow (`fuse.yml`) runs such a game from an app `lota fuse` built. GitHub's Windows runners have no GPU, so nothing has yet tested drawing, input, or a real audio device on Windows, or `lota run`'s Windows save folder below, which comes from reading the code.
- Intel Macs and Linux with musl, such as Alpine, have no gem yet. On those, RubyGems picks Lota's source gem, which stops at install and says so.
- Phones and tablets (iOS, iPadOS, and Android) are planned, and Lota does not build for them yet.

Lota binds LÖVE's graphics, window, keyboard, mouse, touch, joystick and gamepad, sensor, timer, system, event, physics, and thread modules nearly whole, and parts of its filesystem, audio, sound, image, data, font, and math modules. It does not yet bind video. Threads run on Ruby's Ractors, which Ruby 4.0 still calls experimental, so `Lota::Thread` is experimental too, and a thread's code can use fewer of Lota's modules than a LÖVE thread can use of LÖVE's. A game that calls a function Lota has not bound stops with a `NoMethodError`. The [changelog](CHANGELOG.md) lists what each release added.

## Installation

Lota is not on RubyGems.org. Each [GitHub release](https://github.com/setdef/Lota/releases) carries a precompiled gem for each platform and a `SHA256SUMS` file. The gem carries LÖVE's engine and the libraries it uses, so installing it compiles nothing.

Download the gem for your platform, check it, and install it:

```sh
version=0.1.3
platform=arm64-darwin   # or x86_64-linux-gnu, or aarch64-linux-gnu
curl -LO "https://github.com/setdef/Lota/releases/download/v$version/lota-$version-$platform.gem"
curl -LO "https://github.com/setdef/Lota/releases/download/v$version/SHA256SUMS"
shasum -a 256 --check --ignore-missing SHA256SUMS
gem install --local "lota-$version-$platform.gem"
lota --version
```

The last line prints `Lota 0.1.3`.

On Windows, download `lota-0.1.3-x64-mingw-ucrt.gem` (or `lota-0.1.3-aarch64-mingw-ucrt.gem` on ARM64) from the release page and run `gem install --local` on it, with RubyInstaller's Ruby.

If your game has a `Gemfile`, put the gem in the game's `vendor/cache` folder instead, ask for the version, and install from there. Add a gem for each platform you work on; Bundler locks every platform it finds a gem for.

```ruby
# Gemfile
source "https://rubygems.org"

gem "lota", "0.1.3"
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
- **Assets** such as images, fonts, and sounds go anywhere in the folder. Lota reads a file name relative to the game's folder, wherever you ran `lota run` from: `Lota::Graphics::Font.new("assets/pixel.ttf", 16)`.

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

### Translating from LÖVE

Lota changes LÖVE's names by a few rules. These cover most tutorial code:

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

`lota` works anywhere as another name for `Lota`, so `lota.graphics.rectangle(...)` and `def lota.update(dt)` read as a tutorial's `love.graphics` and `function love.update(dt)` do. [Translating LÖVE code](doc/guide/translating.md) has every rule, with the cases where Ruby and Lua differ.

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
$ lota fuse path/to/game --identifier com.yourname.MoonPong
dist/Moon Pong-x64-mingw-ucrt.zip
dist/Moon Pong-x64-mingw-ucrt-setup.exe
Built the app for x64-mingw-ucrt only. Run lota fuse on each platform you ship for.
```

Fledge builds for the computer it runs on, so build each platform's app on that platform: on a Mac for macOS, on Windows for Windows, on Linux for Linux. A player gets:

| Platform | What `lota fuse` writes in `dist` |
| --- | --- |
| macOS | `NAME.app`, in a `.tar.gz` and a `.dmg` |
| Windows | `NAME.exe` and what it needs, in a `.zip`, and a `-setup.exe` that installs it without an administrator |
| Linux | A folder with `NAME` and a desktop entry, in a `.tar.gz`, and an AppImage (glibc 2.39 or newer: Ubuntu 24.04, Debian 13) |

The app's name is `conf.rb`'s `t.window.title`, or else `t.title`, or else the game folder's name. It saves under `t.identity`, or under the game folder's name, as `lota run` does. `lota fuse` writes the project it builds from in `dist/fuse-project`, and the game goes in it under `game/<identity>`.

To fuse a game, you need:

- Lota's gem for your platform, installed from the release as above. `lota fuse` puts that very gem file in the app.
- Ruby 4.0, which the app gets a copy of: on Windows, [RubyInstaller](https://rubyinstaller.org/)'s Ruby 4.0 for x64 or ARM64; its MSYS2 tools are not needed.
- Git, and the network: Fledge is not on RubyGems.org, so Bundler fetches it from GitHub, and Fledge downloads its runtime for your platform the first time. On Windows, install [Git for Windows](https://git-scm.com/download/win); on a Mac, `xcode-select --install` installs Git. Fledge carries what it builds installers with, NSIS among them.

The options:

- `--identifier ID` is the reverse-DNS name macOS and Windows know the app by, such as `com.yourname.MoonPong`. Without it the app gets `com.example.<identity>`, a placeholder: replace it before you ship.
- `--app-version VERSION` is the app's version, such as `1.0.0`; without it, Fledge's `0.0.0`. A game's `t.version` names the version of LÖVE it was written for, so it never becomes the app's.
- `--icon PATH` gives the app the icon files at `PATH` in the game's folder, without their extension, as Fledge takes them: `--icon icons/icon` for `icons/icon.icns` (macOS), `icons/icon.ico` (Windows), and `icons/icon-16.png` to `icons/icon-512.png` (Linux). Without it the app has no icon of its own.
- `--sign IDENTITY` signs the app, as Fledge's `--sign` does: a signing identity from your keychain on macOS, a certificate's SHA-1 thumbprint on Windows. Unsigned, Gatekeeper and SmartScreen warn the people who download it.
- `--out DIR` writes to `DIR` instead of `dist`.
- `LOTA_FLEDGE_REF` names another tag or commit of Fledge to build with.

What a fused game does not do yet: restart (`Lota::Event.restart` ends it as a quit does), or run on a phone or tablet. On Windows the app opens no console, so what the game prints goes nowhere, and Ruby's YJIT is not in RubyInstaller's Ruby, so a Windows app runs without it; elsewhere the app turns YJIT on.

## Documentation

| Resource | Description |
| --- | --- |
| `ri Lota::Graphics.rectangle` | The API reference for any class or method, installed with the gem. Most entries name the LÖVE function they translate |
| [`lib/`](lib) | The same reference in the source, for reading on GitHub. Lota does not host its API docs online yet |
| [Translating LÖVE code](doc/guide/translating.md) | Every naming rule, and how Lota differs from Lua where Ruby has no equivalent |
| [LÖVE's wiki](https://love2d.org/wiki/Main_Page) | What each function does. Look up a Lota method under its LÖVE name |
| [CHANGELOG](CHANGELOG.md) | What changed in each release |
| [Agent skill](skills/lota-gamedev/SKILL.md) | A skill for coding agents that write Lota games: where the API is documented, what differs on phones, and how to test and ship. It is in the installed gem (`gem contents lota \| grep SKILL.md`), and `gh skill install setdef/Lota lota-gamedev` or `npx skills add setdef/Lota` installs it from a release |
| [Releases](https://github.com/setdef/Lota/releases) | The gems and their checksums |

## Reporting problems

Lota's GitHub repository does not take issues yet.

## Contributing

Building Lota from source, its tests, and how it checks itself against LÖVE are in [doc/contributors/development.md](doc/contributors/development.md).

## Copyright & License

Lota is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](https://github.com/love2d/love/blob/main/license.txt), © LÖVE Development Team.

Some parts of this program, and of its precompiled gems, come from other sources under their own licenses, and their copyright belongs to their owners. Each file says which, by the [REUSE Specification – Version 3.3](https://reuse.software/spec-3.3/). Each precompiled gem's `REUSE.toml` records them for the compiled extension, which holds LÖVE's engine and the libraries LÖVE bundles, and for each framework, or on Linux and Windows each shared library, the gem carries, and its `LICENSES` folder holds their texts.

The precompiled gem carries FreeType, which it uses under the [FreeType License](ext/lota/licenses/LICENSE-FTL.txt). As that license asks of a binary distribution: the software is based in part of the work of the FreeType Team.

Lota is an independent project. It is not made, endorsed, or supported by the LÖVE Development Team. It builds a modified version of LÖVE's engine.

## How Lota is made

I use three words for how code and prose comes to exist. Code or prose I wrote, I typed by hand, with nothing generated. Code or prose I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code or prose I requested, an agent built with little or no review from me, in the style of a "dark factory."

Lota's design decisions and its agent instructions are wrought. Everything else, the code, tests, build, this README, and the guide, is requested, and the CI gates stand in for review: sanitizers, clang-tidy, the package checks, the delivery jobs that install each gem on a clean runner, and the parity tests against LÖVE. Each commit says which it holds in a `Provenance:` trailer. Under [declare-ai.org](https://declare-ai.org/1.0.0/creative.html), this is creative assistance.
