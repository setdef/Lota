---
name: lota-gamedev
description: Write, test, and ship a 2D game in Ruby with Lota (a Ruby binding of LÖVE's engine; gem "lota", API under Lota::Graphics, Lota::Window, Lota::Audio, and so on). Use when creating or changing a game folder with conf.rb and main.rb, translating LÖVE or love2d Lua code or tutorials to Ruby, handling touch, gamepad, DPI, safe area, or audio on desktop and phones, running `lota run`, packaging with `lota fuse`, or debugging a NoMethodError, a black window, or a crash in a Lota game.
license: CC-BY-SA-4.0
compatibility: Needs Ruby 4.0.1 or newer and a Lota gem from github.com/setdef/Lota/releases (not on RubyGems). A window needs a display; macOS, Linux, and Windows have gems.
metadata:
  repository: https://github.com/setdef/Lota
---

# Writing a game with Lota

Lota runs LÖVE's C++ engine with Ruby in place of Lua. A game written in Lota
behaves as the same game written in LÖVE, and a LÖVE tutorial reads true once
its calls are translated by a few fixed rules. Read the API from the source of
truth below; do not guess a name.

## Where the truth is

- **The API:** the gem's RBS in `sig/` (`gem contents lota | grep sig/`) lists
  every public method with its types, and the RDoc above each method in
  `lib/` (or `ri Lota::Graphics.rectangle`) says what LÖVE function it
  translates and how it differs.
- **LÖVE's behavior:** the LÖVE wiki, under LÖVE's own name for the function.
  Where the wiki describes LÖVE 11 and Lota's RDoc disagrees, Lota's RDoc wins.
- **The translation rules:** [Translating LÖVE code](https://github.com/setdef/Lota/blob/trunk/doc/guide/translating.md).
- **What exists today:** the README's Compatibility section and the
  [CHANGELOG](https://github.com/setdef/Lota/blob/trunk/CHANGELOG.md) (in the
  gem too). A `NoMethodError` on a LÖVE function usually means it is not bound
  yet: check there before working around it.
- **Install and versions:** [README](https://github.com/setdef/Lota/blob/trunk/README.md).
  Use Lota 0.1.3 or newer: earlier gems can crash a game that fetches the same
  engine object every frame (`World#bodies`, `Joystick.joysticks`).

## A game is a folder

```ruby
# conf.rb (optional): settings before the window opens
def Lota.conf(t)
  t.identity = "sample_game"      # the save folder's name
  t.window.title = "Sample Game"
  t.highdpi = true
end

# main.rb: callbacks are methods on Lota
def Lota.load            = (@x = 0)
def Lota.update(dt)      = (@x += 100 * dt)
def Lota.draw            = Lota::Graphics.rectangle(:fill, @x, 10, 20, 20)
def Lota.keypressed(key) = Lota::Event.quit if key == :escape
```

Run it with `lota run` (from the folder) or `lota run path/to/game`. A callback
receives only as many of LÖVE's arguments as it declares. `lota` is a private
alias of `Lota` (`lota.graphics`), as `love` is in LÖVE. The game's folder is
on `$LOAD_PATH`, and files are read relative to it.

## The rules in one breath

Getters drop `get` (`Lota::Graphics.dimensions`), setters become writers
(`Lota::Window.title = "x"`), predicates end in `?`, enums are symbols,
option tables are keywords, several results come back as an Array
(`contents, size = Lota::Filesystem.read(f)`), paired calls take blocks
(`push { ... }`), and every other name is snake_case. When unsure, read the
RBS rather than reasoning from the rule.

## Working method

1. Find the LÖVE function and its Lota name in the RBS before writing a call.
2. Keep game logic in plain Ruby objects that do not touch Lota, so Minitest
   can test them without a window: [references/testing.md](references/testing.md).
3. Run the real game with `lota run`; for a scripted run, add a smoke mode
   (an environment variable that quits after N seconds and prints a line).
4. For phones, touch, gamepads, DPI, safe areas, audio, and sensors, read
   [references/gotchas.md](references/gotchas.md) before designing the input
   and layout; they are the things that differ from a desktop mouse game.
5. Package with `lota fuse`: [references/shipping.md](references/shipping.md).

## Do not

- File a bug or pull request with LÖVE or SDL: they accept no contribution
  made with generative AI. Report a defect in Lota to Lota's maintainer with
  what you ran, what happened, and the Lota version.
- Imitate or block a person's mouse or keyboard in a test, or grab the
  desktop focus; see the testing reference for the lock that asks a person
  to step away.
- Copy LÖVE's name into your own game's module, command, or product names.
