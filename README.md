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
- **[DragonRuby Game Toolkit](https://dragonruby.org/)** has free and paid tiers, ships its own Ruby runtime, and exports games to the web, desktops, and (on its Pro tier) phones. Lota runs on the Ruby 4.1 you install, with your usual gems. Its gems are for desktops; a phone build is experimental, and compiles from source.
- **[LÖVE](https://love2d.org)** itself runs games written in Lua. Lota runs the same engine with Ruby in place of Lua.

## Compatibility

| Platform | Gem platform | Status |
| --- | --- | --- |
| macOS 15 or newer on Apple Silicon | `arm64-darwin` | Released |
| Linux with glibc 2.35 or newer (Ubuntu 22.04, Debian 12, Fedora 36, and later) on x86_64 | `x86_64-linux-gnu` | Released |
| The same Linux on arm64 | `aarch64-linux-gnu` | Released |
| Windows on x64, with [RubyInstaller](https://rubyinstaller.org/)'s Ruby | `x64-mingw-ucrt` | Released |
| Windows on ARM64, with RubyInstaller's Ruby | `aarch64-mingw-ucrt` | Released |
| iPhone, iPad, and Android | none | Experimental, built from source |

- Lota needs Ruby 4.1. Until Ruby 4.1.0 is released, around Christmas 2026, that means a preview, such as 4.1.0-preview1. On Windows, RubyInstaller publishes no 4.1 preview, so Lota's Windows gems are built and tested on one day's head build of RubyInstaller, the copy [Fledge](https://github.com/setdef/Fledge)'s release keeps, which `.github/windows_ruby.env` names. Use that build: another day's head build can have another ABI, and need not load Lota's gem. Ruby 4.0 is not supported. Lota 1.0.0 waits for Ruby 4.1.0.
- On Linux, a game needs an X11 or Wayland desktop with OpenGL, as a LÖVE game does. CI runs the Linux tests on X11.
- On Windows, CI runs Lota's tests, Lövetest's among them, on Mesa's software OpenGL, as LÖVE's own CI does, installs the gem and runs a game from it, and runs apps that `lota fuse` built. GitHub's Windows runners have no GPU and no audio device, so those checks happen on a PC instead: a game has been played on a Windows PC, and Lövetest passes on an NVIDIA RTX 4090 with both Vulkan and OpenGL.
- Intel Macs and Linux with musl, such as Alpine, have no gem yet. On those, RubyGems picks Lota's source gem, which stops at install and says so.
- Phones and tablets have no gem yet. A game builds for them with [Fledge](https://github.com/setdef/Fledge) and a clone of Lota, or for iPhone and iPad from your game's CI: [Building a game for iPhone, iPad, and Android](doc/guide/phones.md) has both routes. Games have run in the iOS Simulator, on Android emulators, on real iPads and iPhones, and on one Android phone.

Lota binds every module of LÖVE's. Its threads are Ruby Ractors, which Ruby still calls experimental: a thread's code runs in a Ractor of its own, and talks to the game through channels, as in LÖVE. A few functions are not bound yet, and a game that calls one stops with a `NoMethodError`. The [changelog](CHANGELOG.md) lists what each release added.

## Installation

Lota is not on RubyGems.org. Each [GitHub release](https://github.com/setdef/Lota/releases) carries a precompiled gem for each platform and a `SHA256SUMS` file. The gem carries LÖVE's engine and the libraries it uses, so installing it compiles nothing.

Download the gem for your platform from the latest release, check it, and install it. Set `version` to the latest release's number, which the releases page shows:

```sh
version=VERSION
platform=arm64-darwin   # or x86_64-linux-gnu, or aarch64-linux-gnu
curl -LO "https://github.com/setdef/Lota/releases/download/v$version/lota-$version-$platform.gem"
curl -LO "https://github.com/setdef/Lota/releases/download/v$version/SHA256SUMS"
shasum -a 256 --check --ignore-missing SHA256SUMS
gem install --local "lota-$version-$platform.gem"
lota --version
```

The last line prints `Lota` and the version you installed.

On Windows, download `lota-VERSION-x64-mingw-ucrt.gem` (or `lota-VERSION-aarch64-mingw-ucrt.gem` on ARM64) from the release page and run `gem install --local` on it, with RubyInstaller's Ruby.

If your game has a `Gemfile`, put the gem in the game's `vendor/cache` folder instead, ask for the version, and install from there. Add a gem for each platform you work on; Bundler locks every platform it finds a gem for.

```ruby
# Gemfile
source "https://rubygems.org"

gem "lota", "VERSION"   # the version you downloaded
```

```sh
bundle install --local
bundle exec lota run
```

## A first game

A Lota game is a folder. `lota run` runs the one in the current folder, and `lota run path/to/game` runs the one at that path. This game has two files. It slides a square across the window and quits when you press Escape.

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

```console
$ lota run
window 800x600
```

An 800 by 600 window opens, titled "Hello, Lota", with the text in the top left and a white square moving to the right. It wraps around at the edge. Escape closes the window and ends the program.

- **`main.rb`** holds your game. It defines callbacks as methods on `Lota`. Each is optional, and Lota passes a callback only as many arguments as it declares, so `def Lota.keypressed(key)` receives the key alone.
- **`conf.rb`** is optional. Its `Lota.conf(t)` runs before the window opens, to set the window's size and title, name your save folder (`t.identity = "asteroids"`), or turn modules off (`t.modules.physics = false`). The settings keep LÖVE's names.
- **Other Ruby files** sit beside `main.rb`, and `require "player"` loads `player.rb` from the game's folder.
- **Assets** such as images, fonts, and sounds go anywhere in the folder, and Lota reads a file name relative to it.

| Callback | When Lota calls it |
| --- | --- |
| `Lota.load(arguments)` | Once, after `main.rb` loads |
| `Lota.update(dt)` | Every frame, with the seconds since the last frame |
| `Lota.draw` | Every frame, after `update`, on a window cleared to the background color |
| `Lota.keypressed(key, scancode, isrepeat)` | When a key goes down, with the key as a Symbol, such as `:escape` |
| `Lota.mousepressed(x, y, button)` | When a mouse button goes down |
| `Lota.resize(width, height)` | When the window changes size |
| `Lota.quit` | When the game is about to quit; return `true` to keep it running |

The rest of LÖVE's callbacks work the same way, under LÖVE's names.

## The next things you reach for

Most games need the same few things beyond a rectangle. With an image at `images/ship.png` and a sound at `sounds/laser.wav` in the game folder, this `main.rb` draws shapes in a color, prints text in a font of your choosing, draws the ship and moves it with the arrow keys, follows the mouse, plays a sound on a click, and remembers how many shots you fired from one run to the next:

```ruby
# main.rb
def Lota.load
  @ship = Lota::Graphics::Image.new("images/ship.png")
  @laser = Lota::Audio::Source.new("sounds/laser.wav", :static)
  Lota::Graphics.font = Lota::Graphics::Font.new(24)
  @x = 400
  shots, = Lota::Filesystem.read("shots.txt")   # nil when there is no such file
  @shots = shots.to_i
end

def Lota.update(dt)
  @x -= 200 * dt if Lota::Keyboard.down?(:left)
  @x += 200 * dt if Lota::Keyboard.down?(:right)
end

def Lota.draw
  mouse_x, mouse_y = Lota::Mouse.position
  Lota::Graphics.color = 1, 1, 0
  Lota::Graphics.line(@x, 300, mouse_x, mouse_y)
  Lota::Graphics.circle(:fill, mouse_x, mouse_y, 8)
  Lota::Graphics.color = 1, 1, 1
  Lota::Graphics.draw(@ship, @x, 300)
  Lota::Graphics.print("Shots: #{@shots}", 20, 20)
end

def Lota.mousepressed(x, y, button)
  return unless button == 1

  @laser.clone.play   # a copy, so shots overlap
  @shots += 1
end

def Lota.quit
  Lota::Filesystem.write("shots.txt", @shots.to_s)
  false
end
```

Three things in it differ from Lua.

- **A function that can return several values always returns an Array**, on success and on failure. `Lota::Filesystem.read` returns `[contents, size]` or `[nil, message]`, so `shots, = ...` takes the first. An Array is always true in Ruby, even `[nil, message]`, so where Lua writes `if love.filesystem.write(...) then`, write `if Lota::Filesystem.write(...).first`.
- **Setters are writers.** `love.graphics.setColor(1, 1, 0)` is `Lota::Graphics.color = 1, 1, 0`, and getters drop `get`: `love.graphics.getWidth()` is `Lota::Graphics.width`.
- **LÖVE's names for things are Symbols.** `"left"`, `"static"`, and `"escape"` are `:left`, `:static`, and `:escape`.

For whole games to read, Lota's repository holds Ruby translations of three published LÖVE games, which its CI runs frame for frame against the originals: the [arkanoid tutorial](test/games/arkanoid), [Gravity-Wars](test/games/gravity_wars), and [KleleAtoms](test/games/klele_atoms).

## Coming from LÖVE

A few fixed rules turn each LÖVE name into Lota's, so a tutorial line reads as Lota code without a lookup. These rows cover most lines:

| LÖVE (Lua) | Lota (Ruby) |
| --- | --- |
| `function love.update(dt)` | `def Lota.update(dt)` |
| `love.graphics.rectangle("fill", x, y, w, h)` | `Lota::Graphics.rectangle(:fill, x, y, w, h)` |
| `love.graphics.newImage("ship.png")` | `Lota::Graphics::Image.new("ship.png")` |
| `love.audio.newSource("laser.wav", "static")` | `Lota::Audio::Source.new("laser.wav", :static)` |
| `love.graphics.getDimensions()` | `Lota::Graphics.dimensions` |
| `love.graphics.setColor(1, 1, 0)`, `love.graphics.getColor()` | `Lota::Graphics.color = 1, 1, 0`, `Lota::Graphics.color` |
| `love.mouse.setPosition(x, y)` | `Lota::Mouse.position = x, y` |
| `x, y = love.mouse.getPosition()` | `x, y = Lota::Mouse.position` |
| `love.keyboard.isDown("space")` | `Lota::Keyboard.down?(:space)` |
| `if love.filesystem.write(name, text) then` | `if Lota::Filesystem.write(name, text).first` |
| `love.window.setMode(800, 600, {resizable = true})` | `Lota::Window.set_mode(800, 600, resizable: true)` |
| `love.graphics.push()` ... `love.graphics.pop()` | `Lota::Graphics.push { ... }` |
| `body:applyForce(fx, fy)` | `body.apply_force(fx, fy)` |

In short: modules keep their names, and a module's `new…` functions become `Class.new`; getters drop `get`; setters become writers; predicates drop `is` and gain `?`; names LÖVE uses as strings become Symbols; option tables become keyword arguments; paired calls such as `push` and `pop` gain a block form; and method names become snake_case. `lota` works anywhere as another name for `Lota`, so `def lota.update(dt)` reads as `function love.update(dt)` does. [Translating LÖVE code](doc/guide/translating.md) has every rule, and the places where Ruby and Lua differ.

## Saved files

LÖVE's filesystem reads from your game's folder and writes to a save folder. Lota names the save folder after your game's folder, or after `t.identity` if `conf.rb` sets one:

| System | Save folder |
| --- | --- |
| macOS | `~/Library/Application Support/Lota/<identity>` |
| Linux | `$XDG_DATA_HOME/lota/<identity>`, or `~/.local/share/lota/<identity>` |
| Windows | `%APPDATA%\Lota\<identity>` |

LÖVE's `love` program saves in the same places, in a `LOVE` folder (`love` on Linux) instead of `Lota`. A game built with `lota fuse` ([below](#sharing-a-game)) saves where a fused LÖVE game saves, in `<identity>` directly under the same folder, without `Lota`: `%APPDATA%\<identity>` on Windows, for one. `Lota::Filesystem.save_directory` returns the path.

## Errors

When your game raises an error, Lota prints it with its Ruby backtrace and shows LÖVE's error screen in the game's window: the error and backtrace in white on blue. Press Ctrl+C to copy them. Press Escape or close the window to quit, with exit status 1. To show something else, define `Lota.errorhandler(error)`, as a LÖVE game defines `love.errorhandler`.

## Sharing a game

`lota fuse` builds your game into an app that a player runs without Ruby, as LÖVE fuses a game into an executable of its own. Run it in the game's folder, or name the folder:

```console
$ lota fuse path/to/game --identifier com.example.SampleGame
dist/Sample Game-x64-mingw-ucrt.zip
dist/Sample Game-x64-mingw-ucrt-setup.exe
Built the app for x64-mingw-ucrt only. Run lota fuse on each platform you ship for.
```

It builds for the computer it runs on, so build each platform's app on that platform. [Sharing a game](doc/guide/sharing.md) has what each platform gets, what `lota fuse` needs, signing and notarizing, leaving files out, and how it ships your gems.

## Documentation

| Resource | Description |
| --- | --- |
| `ri Lota::Graphics.rectangle` | The API reference for any class or method, installed with the gem. Most entries name the LÖVE function they translate |
| [`lib/`](lib) | The same reference in the source, for reading on GitHub. Lota does not host its API docs online yet |
| [Translating LÖVE code](doc/guide/translating.md) | Every naming rule, and how Lota differs from Lua where Ruby has no equivalent |
| [Sharing a game](doc/guide/sharing.md) | What `lota fuse` writes for each platform, what it needs, signing and notarizing, leaving files out, and how it ships your gems |
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
