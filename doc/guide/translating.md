<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Translating LÖVE Code

LÖVE's tutorials, wiki, and example games are written in Lua. Lota keeps LÖVE's modules, classes, and functions, and changes their names by fixed rules, so you can turn any line of a tutorial into Ruby without guessing. This page lists those rules, then the places where Ruby and Lua differ enough that a translation needs more than a new name.

Look up what a function does on [LÖVE's wiki](https://love2d.org/wiki/Main_Page), under its LÖVE name. Look up its Ruby signature with `ri`, for example `ri Lota::Graphics.rectangle`.

## The naming rules

| Rule | LÖVE (Lua) | Lota (Ruby) |
| --- | --- | --- |
| Modules keep their names. | `love.graphics` | `Lota::Graphics` |
| A `new` function becomes a constructor. | `love.graphics.newSpriteBatch(img, 1000)` | `Lota::Graphics::SpriteBatch.new(img, 1000)` |
| Getters drop `get`. | `love.graphics.getDimensions()` | `Lota::Graphics.dimensions` |
| Several results come back as one Array, on success and on failure. | `x, y = love.mouse.getPosition()` | `x, y = Lota::Mouse.position` |
| Setters become writers. | `love.window.setTitle("Game")` | `Lota::Window.title = "Game"` |
| A setter of several values takes them after `=`. | `love.mouse.setPosition(x, y)` | `Lota::Mouse.position = x, y` |
| A setter that returns a result stays a method. | `ok = love.window.setFullscreen(true)` | `ok = Lota::Window.set_fullscreen(true)` |
| Predicates drop `is`, `has`, or `are`, and gain `?`. | `love.mouse.isDown(1)`, `love.window.hasFocus()` | `Lota::Mouse.down?(1)`, `Lota::Window.focus?` |
| Enum strings become Symbols. | `"fill"`, `"escape"` | `:fill`, `:escape` |
| A table of options becomes keywords. | `love.window.setMode(800, 600, {resizable = true})` | `Lota::Window.set_mode(800, 600, resizable: true)` |
| A pair of calls gains a block form. | `love.graphics.push()` ... `love.graphics.pop()` | `Lota::Graphics.push { ... }` |
| A function argument becomes a block. | `texture:renderTo(function() ... end)` | `texture.render_to { ... }` |
| Every other name becomes snake_case. | `body:applyForce(fx, fy)`, `getDPIScale` | `body.apply_force(fx, fy)`, `dpi_scale` |
| Lua iterators become Enumerators. | `for n, a, b in love.event.poll() do` | `Lota::Event.poll.each { \|name, *args\| ... }` |

A Lua method call (`body:applyForce`) becomes a Ruby method call (`body.apply_force`). Metamethods become operators: a Transform's `__mul` is `*`.

## Callbacks and settings

Where a LÖVE game defines `function love.update(dt)`, a Lota game defines `def Lota.update(dt)`. Callbacks are ordinary methods, so the rest of what LÖVE code does with them works too:

| LÖVE | Lota |
| --- | --- |
| `love.draw()` | `Lota.draw` |
| `if love.update then` | `if Lota.respond_to?(:update)` |
| `return` inside a callback | `return` inside the method |
| saving and wrapping `love.update` | prepending a module to `Lota.singleton_class` and calling `super` |

Lua passes a function every argument and ignores the ones it does not name. Lota does the same: a callback receives as many of LÖVE's arguments as it declares. A required parameter beyond them receives `nil`, as in Lua, and an optional one keeps its default. Numbers LÖVE holds as integers, such as a mouse button or a resized window's size, arrive as Integers, and the rest, such as positions and `dt`, as Floats.

`conf.rb`'s settings keep LÖVE's spelling, which runs lowercase words together (`t.window.fullscreentype`, `t.window.minwidth`). A setting LÖVE does not know is accepted and ignored, and a setting never set reads as `nil`, as a missing key does in Lua. With `t.modules.timer = false`, `lota.timer` is `nil`, as `love.timer` is.

A game whose `t.version` names a version of LÖVE that Lota's engine is not compatible with gets LÖVE's compatibility warning, printed and shown in a dialog before the window opens.

## Results and records

Where a Lua function returns several values, the Ruby method returns an Array of all of them, including when it fails. Where Lua code tests only the first result, take `.first`:

```ruby
contents, size = Lota::Filesystem.read("save.dat")
contents, message = Lota::Filesystem.read("missing.dat")   # contents is nil
saved = Lota::Filesystem.write("save.dat", data).first      # if love.filesystem.write(...) then
```

A table LÖVE returns as a record is a frozen `Data` object with LÖVE's field names: `Lota::Filesystem.info("save.dat")&.size` is the file's size, or `nil` when there is no such file. A record also answers `[]` with a field's name, as a Lua table answers brackets, so `Lota::Graphics.texture_types["2d"]` reads the one field no Ruby method can be named.

A table of options becomes keywords: `Lota::Graphics.set_canvas(mask, stencil: true)` translates `love.graphics.setCanvas({mask, stencil = true})`, and `Lota::Graphics.canvas = mask` is the plain form.

## Blocks and callables

A function LÖVE keeps to call later takes a block or any object that answers `call`, as Ruby's `Signal.trap` does. `Lota::Graphics.capture_screenshot { |image_data| ... }` receives the next frame the window shows.

A physics World takes four contact callbacks, more than a method's one block, so it takes them as a writer: `world.callbacks = begin_contact, end_contact, pre_solve, post_solve`, each anything that answers `call`, or `nil`. `world.contact_filter = ->(a, b) { ... }` decides which Shapes collide. Each receives only as many arguments as it declares, as your game's callbacks do.

## Objects and types

LÖVE's root types are classes: every engine object is a `Lota::Object`, and every Data, such as an ImageData, SoundData, FileData, or ByteData, is a `Lota::Data` too, as each inherits from Object and Data in LÖVE. `Lota::Data`'s class methods are `love.data`'s, and given the container `:data` they return an object of `Lota::Data` itself, a plain Data with Data's methods, as LÖVE's do. `Lota::Data.hash(:string, :md5, s)` is `love.data.hash`; with no arguments, `Lota::Data.hash` is Ruby's own `Object#hash`. In the same way `Lota::Sensor.name(:accelerometer)` is `love.sensor.getName`, and `Lota::Sensor.name` is Ruby's `Module#name`.

Every engine object answers `object_type` with LÖVE's name for its type (`"Texture"`), and `type_of?` for that type and its parents (`texture.type_of?(:Object)`), as LÖVE's `type` and `typeOf` do. A type's name is a name, so it is a Symbol; a String names the same type. `type` is another name for `object_type`, except on a Body, Shape, Joint, Source, or Cursor. Those also have LÖVE's `getType`, which Lota names `get_type` (`body.get_type` is `:dynamic`), and they have no `type`, so a call meant for one never answers the other.

LÖVE's `__tostring` and `__eq`, which every object has, are `to_s` and `==`: `texture.to_s` is `"Texture: 0x0127c3a4f0"`, and two objects are `==` when they hold the same engine object. `release` is LÖVE's `release`: it returns `true` the first time, and after it any call that uses the object raises `RuntimeError` ("Cannot use object after it has been released."). As in LÖVE, the engine object is freed then if nothing else holds it, so a released File is closed at once; released inside a block a method of the object yields to, it is freed when that method returns.

An engine object Lota hands back, as `Lota::Graphics.canvas` hands back the canvas you set, or `world.bodies` the Bodies you made, is the same Ruby object you made, until you release it. `clone` and `dup` of a SoundData, ImageData, FileData, Decoder, or Source make LÖVE's copy, a new engine object.

Where LÖVE reads a whole number, such as a font's size, Lota takes a Float too and cuts it toward 0, as LuaJIT does: `Lota::Graphics::Font.new(12.5)` is a 12-pixel font.

A Shader has LÖVE's `send`, which replaces Ruby's `Object#send` on a Shader: `glow.send("strength", 1.5)` sends a uniform. Use `__send__` for Ruby's.

## Numbers that match LÖVE's

Some of LÖVE's functions are LuaJIT code rather than C++, such as `ImageData:getPixel` and `SoundData:getSample`. Lota translates that code and computes in double precision, as LuaJIT does, so `image_data.pixel(x, y)` and `sound.sample(0)` return what LÖVE returns.

Physics distances are in pixels, divided by `Lota::Physics.meter`, which is 30 by default, as in LÖVE.

## Deprecated names

A setting or function LÖVE 12 has deprecated, such as `t.window.highdpi` or `love.graphics.newText`, works as it does in LÖVE. Its first use prints LÖVE's notice of what replaced it.
