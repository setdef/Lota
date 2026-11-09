<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Translating LÖVE Code

LÖVE's tutorials, wiki, and example games are written in Lua. Lota keeps LÖVE's modules, classes, and functions, and renames them by fixed rules, so you can turn any line of a tutorial into Ruby without guessing. This page gives you those rules, then the places where Ruby and Lua differ enough that a translation needs more than a new name.

Look up what a function does on [LÖVE's wiki](https://love2d.org/wiki/Main_Page), under its LÖVE name. Look up its Ruby signature with `ri`, such as `ri Lota::Graphics.rectangle`; most entries name the LÖVE function they translate. When a rule here is not enough, the full list, with the rules that only matter inside Lota and the reasons behind each, is in [translation.md](../contributors/design/translation.md).

## The rules

Apply every rule that fits, in any order: `getDPIScale` drops `get` and becomes `dpi_scale`.

### Names

| Rule | LÖVE (Lua) | Lota (Ruby) |
| --- | --- | --- |
| Modules keep their names. | `love.graphics` | `Lota::Graphics` |
| Getters drop `get`. | `love.graphics.getDimensions()` | `Lota::Graphics.dimensions` |
| Setters become writers. | `love.window.setTitle("Game")` | `Lota::Window.title = "Game"` |
| A setter of several values takes them all after `=`. | `love.mouse.setPosition(x, y)` | `Lota::Mouse.position = x, y` |
| Predicates drop `is`, `has`, or `are`, and gain `?`. | `love.mouse.isDown(1)`, `love.window.hasFocus()` | `Lota::Mouse.down?(1)`, `Lota::Window.focus?` |
| Every other name becomes snake_case, and a method call takes a dot. | `body:applyForce(fx, fy)` | `body.apply_force(fx, fy)` |
| An acronym, or a word cut to one letter, is one word. | `love.window.getVSync()` | `Lota::Window.vsync` |
| Digits stay with the word before them. | `transform:isAffine2DTransform()` | `transform.affine2d_transform?` |
| A string LÖVE uses as a name becomes a Symbol, spelled as LÖVE spells it. | `love.graphics.rectangle("fill", x, y, w, h)` | `Lota::Graphics.rectangle(:fill, x, y, w, h)` |

Callbacks keep their names, so `function love.update(dt)` becomes `def Lota.update(dt)`. A Lua metamethod takes Ruby's name for it: `__mul` is `*`, `__eq` is `==`, and `__tostring` is `to_s`. Key names are Symbols too, `:escape` and `:space`, and since LÖVE 12 takes any UTF-8 character as a key, so does Lota. Enum Symbols keep LÖVE's spelling, even where it is not snake_case: `:DXT1`, `:ETC2rgb`.

### Making objects

| Rule | LÖVE (Lua) | Lota (Ruby) |
| --- | --- | --- |
| A module's `new` function becomes a class's constructor. | `love.graphics.newSpriteBatch(img, 1000)` | `Lota::Graphics::SpriteBatch.new(img, 1000)` |
| A class sits in the module of the folder LÖVE keeps it in. | `love.image.newImageData(w, h)` | `Lota::Image::ImageData.new(w, h)` |
| An object's own `new` methods stay methods. | `texture:newImageData()` | `texture.new_image_data` |
| A `new` function that makes several objects stays a method. | `body, shape = love.physics.newCircleBody(world, "dynamic", x, y, r)` | `body, shape = Lota::Physics.new_circle_body(world, :dynamic, x, y, r)` |
| A `new` function for a type of another name gets a module whose `new` makes it. | `love.graphics.newCanvas(w, h)` | `Lota::Graphics::Canvas.new(w, h)`, a `Texture` |
| `clone` keeps its name, and `dup` makes the same copy. | `source:clone()` | `source.clone` |

A canvas, an image, a cube texture, and a texture view are all LÖVE's Texture, so `Lota::Graphics::Canvas.new`, `Image.new`, `CubeTexture.new`, and `TextureView.new` all return a `Lota::Graphics::Texture`. Each of those modules answers `===` by asking LÖVE, so `Canvas === texture` is `texture.canvas?`, and a `case` statement still sorts textures. Where LÖVE cannot tell what made an object, the module matches every object of its class: `Image === texture` is true of every Texture. A Buffer is LÖVE's GraphicsBuffer, so `Lota::Graphics::Buffer.new` returns a `Lota::Graphics::GraphicsBuffer`. Where a module and a class would share a full name, they are one: `Lota::Data` holds `love.data`'s functions and is also the class every Data inherits from.

### Results

| Rule | LÖVE (Lua) | Lota (Ruby) |
| --- | --- | --- |
| A function that can return several values always returns an Array. | `x, y = love.mouse.getPosition()` | `x, y = Lota::Mouse.position` |
| A setter that returns a result stays a `set_` method. | `ok = love.window.setFullscreen(true)` | `ok = Lota::Window.set_fullscreen(true)` |
| A setter whose first value can be a Data stays a `set_` method. | `mesh:setVertices(vertices)` | `mesh.set_vertices(vertices)` |
| A record LÖVE returns becomes a frozen `Data` object. | `love.filesystem.getInfo(f).size` | `Lota::Filesystem.info(f).size` |
| A table LÖVE fills in for you to reuse is dropped. | `love.graphics.getStats(stats)` | `Lota::Graphics.stats` |
| A Lua iterator becomes an Enumerator, which also takes a block. | `for n, a, b in love.event.poll() do` | `Lota::Event.poll.each { \|name, *args\| ... }` |

### Arguments and blocks

| Rule | LÖVE (Lua) | Lota (Ruby) |
| --- | --- | --- |
| A table of options becomes keywords. | `love.window.setMode(800, 600, {resizable = true})` | `Lota::Window.set_mode(800, 600, resizable: true)` |
| A pair of calls that opens and closes within a frame also has a block form. | `love.graphics.push()` ... `love.graphics.pop()` | `Lota::Graphics.push { ... }` |
| A block form of an opening call runs the block only if opening succeeds. | `if file:open("r") then ... file:close() end` | `file.open(:r) { ... }` |
| A function argument becomes a block. | `texture:renderTo(function() ... end)` | `texture.render_to { ... }` |
| A function LÖVE keeps for later can be anything that answers `call`. | `world:setContactFilter(f)` | `world.contact_filter = f` |
| A setter that keeps a function stays a writer. | `world:setCallbacks(b, e, pre, post)` | `world.callbacks = b, e, pre, post` |
| A loaded Lua chunk becomes a Proc, and its `...` is its `ARGV`. | `chunk = love.filesystem.load("level.lua")` | `chunk = Lota::Filesystem.load("level.rb").first` |

## Where Ruby and Lua differ

The rules settle names. A few things LÖVE code does rest on how Lua works, and they need a word of their own.

### Callbacks are methods

Where a LÖVE game defines `function love.update(dt)`, a Lota game defines `def Lota.update(dt)`. A callback is an ordinary method, so the rest of what LÖVE code does with callbacks works too: `if love.update then` becomes `if Lota.respond_to?(:update)`, a `return` inside a callback is a `return` inside the method, and saving and wrapping `love.update` becomes prepending a module to `Lota.singleton_class` and calling `super`.

`lota` works anywhere as another name for `Lota`, so `lota.graphics.rectangle(...)` and `def lota.update(dt)` read as a tutorial's `love.graphics` and `function love.update(dt)` do.

Lua passes a function every argument and ignores the ones it does not name. Lota does the same: a callback receives as many of LÖVE's arguments as it declares, so `def Lota.keypressed(key)` gets the key alone. A required parameter beyond LÖVE's arguments receives `nil`, as in Lua, and an optional one keeps its default.

### Settings keep LÖVE's spelling

`conf.rb`'s settings keep LÖVE's names, which run lowercase words together: `t.window.fullscreentype`, `t.window.minwidth`. A setting LÖVE does not know is accepted and ignored, and a setting never set reads as `nil`, as a missing key does in Lua. With `t.modules.timer = false`, `lota.timer` is `nil`, as `love.timer` is.

A game whose `t.version` names a version of LÖVE that Lota's engine is not compatible with gets LÖVE's compatibility warning, printed and shown in a dialog before the window opens.

### Several results come back as one Array

Where a Lua function returns several values, the Ruby method returns an Array of all of them, on success and on failure alike. Destructure it as you would in Lua. Where Lua code tests only the first result, take `.first`, because an Array is always true in Ruby, even `[false]` or `[nil, message]`:

```ruby
contents, size = Lota::Filesystem.read("save.dat")
contents, message = Lota::Filesystem.read("missing.dat")   # contents is nil
saved = Lota::Filesystem.write("save.dat", data).first      # if love.filesystem.write(...) then
```

### Records are frozen Data

A table LÖVE returns as a record is a frozen `Data` object with LÖVE's field names: `Lota::Filesystem.info("save.dat")&.size` is the file's size, or `nil` when there is no such file. A record also answers `[]` with a field's name, as a Lua table answers brackets, so `Lota::Graphics.texture_types["2d"]` reads the one field no Ruby method can be named.

A table of options becomes keywords: `Lota::Graphics.set_canvas(mask, stencil: true)` translates `love.graphics.setCanvas({mask, stencil = true})`, and `Lota::Graphics.canvas = mask` is the plain form.

### Functions LÖVE keeps for later

A function LÖVE keeps to call later takes a block, or any object that answers `call`, as Ruby's `Signal.trap` does. `Lota::Graphics.capture_screenshot { |image_data| ... }` receives the next frame the window shows.

A physics World takes four contact callbacks, more than a method's one block, so it takes them as a writer: `world.callbacks = begin_contact, end_contact, pre_solve, post_solve`, each anything that answers `call`, or `nil`. `world.contact_filter = ->(a, b) { ... }` decides which Shapes collide. Each receives only as many arguments as it declares, as your callbacks do.

A pair's block form is the Lua that tests the first call before it makes the second. `file.open(:r) { |f| f.read.first }` is `if file:open("r") then ... file:close() end`: when the file opens, the block gets it, the file closes when the block ends, even on an error, and the block's value comes back. When the file does not open, the block does not run, and you get what `file.open(:r)` returns, such as `[nil, message]`. Pairs that run across frames, such as a Source's `play` and `stop`, have no block form.

`love.filesystem.load` loads a file of Lua as a function; `Lota::Filesystem.load("level.rb")` loads a file of Ruby as a Proc, in an Array. It reads the file where LÖVE's filesystem finds it, including the save folder and mounted archives, which `require` does not search. A syntax error raises at once, and the code runs, at the top level, each time you call the Proc, with the Proc's arguments as its `ARGV`.

### Objects and their types

LÖVE's root types are classes: every engine object is a `Lota::Object`, and every Data, such as an ImageData, SoundData, FileData, or ByteData, is a `Lota::Data` too. `Lota::Data`'s class methods are `love.data`'s, so `Lota::Data.hash(:string, :md5, s)` is `love.data.hash`, while `Lota::Data.hash` with no arguments is Ruby's own `Object#hash`. In the same way, `Lota::Sensor.name(:accelerometer)` is `love.sensor.getName`, and `Lota::Sensor.name` is Ruby's `Module#name`.

Every engine object answers `object_type` with LÖVE's name for its type as a String, such as `"Texture"`, as LÖVE's `type` does. `type` is another name for it. `type_of?` is LÖVE's `typeOf`, and asks about the type and its parents: `texture.type_of?(:Drawable)` and `texture.type_of?("Object")` are both true. A Body, Shape, Joint, Source, or Cursor also has LÖVE's `getType`, which means something else there, so Lota names it `get_type` (`body.get_type` is `:dynamic`), with `set_type` beside it, and those classes have no `type` at all. A call meant for one then fails loudly instead of answering the other.

LÖVE's `__tostring` and `__eq` are `to_s` and `==`: `texture.to_s` is `"Texture: 0x0127c3a4f0"`, and two objects are `==` when they hold the same engine object. `release` is LÖVE's `release`: it returns `true` the first time, and after it any call that uses the object raises `RuntimeError` ("Cannot use object after it has been released."). As in LÖVE, the engine object is freed then if nothing else holds it, so a released File closes at once.

An engine object Lota hands back, as `Lota::Graphics.canvas` hands back the canvas you set or `world.bodies` the Bodies you made, is the same Ruby object you made, until you release it.

A Shader has LÖVE's `send`, which takes the place of Ruby's `Object#send` on a Shader: `glow.send("strength", 1.5)` sends a uniform. Use `__send__` for Ruby's.

A raw pointer, which LÖVE gives Lua from `Data:getPointer`, `Data:getFFIPointer`, and `love.window.getPointer`, is a `Fiddle::Pointer` to the same address, Ruby's own FFI where LuaJIT has its `ffi`: `data.ffi_pointer.to_str` reads a Data's bytes. It is valid only while the Data or the window it points into lives, as in LÖVE. Lota does not depend on Fiddle, so add `gem "fiddle"` to your game's Gemfile to use them.

### Numbers

Lua has one kind of number, and Ruby has two. Numbers LÖVE's C++ holds as integers arrive as Integers, such as a mouse button, a joystick's button, or a resized window's size while graphics is open, and the rest arrive as Floats, such as positions and `dt`. Where LÖVE reads a whole number, such as a font's size, Lota takes a Float too and cuts it toward 0, as LuaJIT does: `Lota::Graphics::Font.new(12.5)` is a 12-pixel font.

Some of LÖVE's functions are LuaJIT code rather than C++, such as `ImageData:getPixel` and `SoundData:getSample`. Lota translates that code and computes in double precision, as LuaJIT does, so `image_data.pixel(x, y)` and `sound.sample(0)` return what LÖVE returns.

Physics distances are in pixels, divided by `Lota::Physics.meter`, which is 30 by default, as in LÖVE.

### Errors name Ruby's methods

LÖVE's error messages come through word for word, except that they name Lota's modules and methods: where LÖVE says `love.window.setTitle`, Lota says `Lota::Window.title=`.

### Deprecated names

A setting or function LÖVE 12 has deprecated, such as `t.window.highdpi` or `love.graphics.newText`, works as it does in LÖVE. Its first use prints LÖVE's notice of what replaced it.
