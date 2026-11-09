<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Translating LÖVE's API into Ruby

A decade of LÖVE tutorials teaches games in Lua. This document holds the rules Lota translates that API by ([ADR 008](../adr/008.md)), the reasons behind them, and the literal mode for copying Lua verbatim.

## The rules

Lota does not make Ruby imitate Lua. It translates LÖVE's API by fixed rules, so that a reader can turn any tutorial line into Ruby without guessing. LÖVE has 793 distinct function names across its `wrap_*.cpp` files (316 `get`, 177 `set`, 71 `is`/`has`/`are`, 68 `new`, and 163 other verbs), and every one of them falls under these rules. The table decides each function's Ruby name and the shape of a call to it; what the function does follows LÖVE's source. Apply every rule that fits, in any order: `getDPIScale` drops `get` by rule 3 and becomes `dpi_scale` by rule 13. Where two rules would disagree, the row says which one wins; where none does, it is a collision, settled as described below.

| # | Rule | LÖVE | Lota |
|---|---|---|---|
| 1 | Modules keep their names. | `love.graphics` | `Lota::Graphics` |
| 2 | A module's `new…` functions become constructors; an object's `new…` methods don't. | `love.graphics.newSpriteBatch(img)`, `texture:newImageData()` | `Lota::Graphics::SpriteBatch.new(img)`, `texture.new_image_data` |
| 3 | Getters drop `get`. | `love.graphics.getDimensions()` | `Lota::Graphics.dimensions` |
| 4 | Functions that can return several values always return an Array. | `x, y = love.mouse.getPosition()`, `if love.filesystem.write(f, s) then` | `x, y = Lota::Mouse.position`, `if Lota::Filesystem.write(f, s).first` |
| 5 | Setters become writers. | `love.window.setTitle("Game")` | `Lota::Window.title = "Game"` |
| 6 | Setters that take several values become writers that take an Array. | `love.mouse.setPosition(x, y)` | `Lota::Mouse.position = x, y` |
| 7 | Setters that return something besides themselves stay `set_` methods. | `ok = love.window.setFullscreen(true)`, `t:setTransformation(x, y, angle)` | `ok = Lota::Window.set_fullscreen(true)`, but `t.transformation = x, y, angle` (it returns `t`) |
| 8 | Predicates drop `is`, `has`, or `are` and gain `?`. | `love.mouse.isDown(1)`, `love.window.hasFocus()` | `Lota::Mouse.down?(1)`, `Lota::Window.focus?` |
| 9 | Strings LÖVE uses as names become symbols, spelled as LÖVE spells them. | `"alpha"`, `"DXT1"`, `key == "escape"` | `:alpha`, `:DXT1`, `key == :escape` |
| 10 | Option tables become keyword arguments. | `love.window.setMode(800, 600, {resizable = true})` | `Lota::Window.set_mode(800, 600, resizable: true)` |
| 11 | Opposite calls on one object that open and close within a frame also gain a block form. | `push()` ... `pop()`, `file:open("r")` ... `file:close()`, but not `source:play()` ... `source:stop()` | `push { ... }`, `file.open(:r) { ... }`, but just `source.play` |
| 12 | Function arguments become blocks. | `texture:renderTo(function() ... end)` | `texture.render_to { ... }` |
| 13 | Method names become snake_case. | `body:applyForce(fx, fy)` | `body.apply_force(fx, fy)` |
| 14 | Integers in LÖVE's C++ become Integers; other numbers become Floats. | `love.resize(800, 600)`, `love.event.quit(3)` | `Lota.resize(800, 600)` while graphics is open, `Lota.resize(800.0, 600.0)` otherwise; exit status `3` |
| 15 | Lua iterators become Ruby Enumerators, which also take a block. | `for n, a, b in love.event.poll() do` | `Lota::Event.poll.each { \|name, *args\| ... }` |
| 16 | `type` returns LÖVE's type name as a String, not a symbol. | `img:type()` | `img.type` and `img.object_type` (`"Texture"`) |
| 17 | Factories that make several objects stay methods, not constructors. | `body, shape = love.physics.newCircleBody(world, "dynamic", x, y, r)` | `body, shape = Lota::Physics.new_circle_body(world, :dynamic, x, y, r)` |
| 18 | Classes take the name LÖVE's `type` reports. | `love.graphics.newBuffer(...)` | `Lota::Graphics::Buffer.new(...)` returns a `Lota::Graphics::GraphicsBuffer` |
| 19 | Types LÖVE defines outside any module, and gives methods, sit directly in `Lota`. | `Object`, `Data` | `Lota::Object`, `Lota::Data` |
| 20 | `clone` keeps its name, and `dup` makes the same copy. | `sound:clone()` | `sound.clone`, `sound.dup` |
| 21 | Where LÖVE's own Lua replaces a C++ function, Lota translates the Lua. | `image_data:getPixel(x, y)` (`wrap_ImageData.lua`) | `image_data.pixel(x, y)` |
| 22 | Names that start with one `_` are LÖVE's internals and get no Lota name. | `love.math._getRandomGenerator()` | none |
| 23 | Error messages use Lota's names; the rest stays word for word. | `"love.image must be loaded..."`, `love.window.setTitle` | `"Lota::Image must be loaded..."`, `Lota::Window.title=` |
| 24 | A Lua chunk becomes a lambda, and its `...` arrives as `ARGV`. | `chunk = love.filesystem.load("level.lua")`, `chunk(1, 2)` | `chunk = Lota::Filesystem.load("level.rb").first`, `chunk.call(1, 2)` |
| 25 | A factory for a class with another name becomes a factory module, whose `new` returns that class. | `love.graphics.newCanvas(w, h)` | `Lota::Graphics::Canvas.new(w, h)`, a `Texture` |
| 26 | A factory module's `===` asks LÖVE whether an object is what that factory makes. | `t:isCanvas()`, `t:getTextureType() == "cube"` | `Canvas === t` is `t.canvas?`, `CubeTexture === t` is `t.texture_type == :cube` |
| 27 | If LÖVE can't tell what a factory made, its factory module's `===` matches every object of the class. | `love.graphics.newImage(f)` | `Image.new(f)` returns a `Texture`, and `Image === t` for every `Texture` |
| 28 | Returned records become frozen Ruby `::Data` objects that also answer `[]`. | `love.filesystem.getInfo(f).size`, `love.graphics.getTextureTypes()["2d"]` | `Lota::Filesystem.info(f).size`, `Lota::Graphics.texture_types["2d"]` |
| 29 | Tables LÖVE fills in for you to reuse are dropped. | `love.graphics.getStats(stats)` | `Lota::Graphics.stats` |
| 30 | A block form of an opening call runs the block only if opening succeeds; otherwise it returns what opening returned. | `if file:open("r") then ... end` | `file.open(:r) { ... }` |
| 31 | A function LÖVE stores for later can be anything that answers `call`. | `world:setContactFilter(f)` | `world.contact_filter = f`, with `f` a lambda, a method, or any object with `call` |
| 32 | A setter that stores a function stays a writer, not a block. | `world:setCallbacks(b, e, pre, post)` | `world.callbacks = b, e, pre, post` |
| 33 | `typeOf` becomes `type_of?`. | `img:typeOf("Object")` | `img.type_of?("Object")` |
| 34 | A class with its own `getType` keeps the `get_` and `set_` on its type methods. | `body:getType()`, `body:setType("static")` | `body.get_type`, `body.set_type(:static)` |
| 35 | A setter whose first value can be a Data stays a `set_` method. | `mesh:setVertices(vertices)`, `mesh:setVertexMap(map)`, `buffer:setArrayData(data)` | `mesh.set_vertices(vertices)`, `mesh.set_vertex_map(map)`, `buffer.set_array_data(data)` |
| 36 | An acronym is one word, and so is a word cut to one letter (`VSync`, `UInt`). | `getDPIScale`, `getVSync` | `dpi_scale`, `vsync` |
| 37 | Digits stay with the word before them. | `getUInt8`, `isAffine2DTransform` | `uint8`, `affine2d_transform?` |
| 38 | Metamethods take Ruby's names. | `__mul`, `__eq`, `__tostring` | `*`, `==`, `to_s` |
| 39 | A class sits in the module of its LÖVE folder. | `GlyphData` (in `font/`) | `Lota::Font::GlyphData` |
| 40 | When these rules give a module and a class the same full Ruby name, they are one class. | `love.data.compress("string", "zlib", s)`, a `Data` | `Lota::Data.compress(:string, :zlib, s)`, a `Lota::Data` |
| 41 | A class with its own `getType` has no `type`, only `object_type`. | `body:type()` | `body.object_type` (`"Body"`) |
| 42 | `type` is also called `object_type`. | `img:type()` | `img.object_type` |

## Why the rules say what they say

Rule 27 makes `Image === texture` true of every Texture because `newImage` is `newTexture`, which can make a canvas too, so no Texture shows that `newImage` did not make it. A PolygonShape likewise cannot show that `newRectangleShape` made it, so `RectangleShape === shape` is true of every PolygonShape.

Rule 35 exists because a writer cannot tell one value that is itself a list or a Data from a list of several values.

Rule 7 exists because a Ruby writer always evaluates to its argument, so a writer would throw the setter's result away. A setter that returns its own object, for Lua-style chaining, loses nothing that way. Rule 7 also keeps LÖVE's two kinds of failure apart. LÖVE raises an error when the caller made a mistake (a bad argument, an unknown enum) and returns `false` when a valid request met a machine that said no: no vibration motor, no fullscreen mode, a display mode refused. A game handles the second kind by falling back, so it stays a return value; Lota raises exactly where LÖVE raises. The setters rule 7 covers today are `setMode`, `setFullscreen`, `setVibration`, `setIcon`, `setRelativeMode`, `setEffect`, `setFilter`, `setOutputSpatialization`, `setMixWithSystem`, `setBuffer`, `setGamepadMapping`, `setPlaybackDevice`, and `setNewFont`, which returns the font it makes. Calling the getter afterward is no substitute for the return value: `setIcon` stores the new icon before the checks that can fail, LÖVE 12 deprecated `getVibration` to always return zero, and `setMixWithSystem` has no getter at all. `t.matrix = :column, *elements` takes the optional layout first, as `Transform:setMatrix` does. Ruby writers do not chain, but `translate`, `rotate`, and `scale` still return the Transform, so `t.translate(1, 2).rotate(0.5)` chains as it does in Lua.

Rule 9 reaches past the `wrap_*.cpp` files: event names, keys, and scancodes come from `src/modules/event/sdl/Event.cpp`. Not every such set is closed. In LÖVE 12 any UTF-8 name is a key, the key of its first character (`src/modules/keyboard/Keyboard.cpp`, lines 36–64), so key symbols are names, not members of a fixed list.

Rule 28's records answer `[]` as a Lua table answers brackets, so a field no Ruby method can be named, such as `getTextureTypes`' `2d`, still reads. A frozen record cannot be filled in, so by rule 29 LÖVE's fill-in argument has nothing left to do.

Rules 11 and 12 follow the Execute Around pattern (Russ Olsen, *Eloquent Ruby*, chapter 18): the method sets up, yields, and undoes the setup in an `ensure`, so a raised error cannot leave the transform stack pushed or a file open. State setters such as `setCanvas` have no named opposite, and need no block form, because `push(:all) { ... }` already saves and restores all of them. `love.filesystem.openFile` gets none either: it opens on the module and closes on the File, not on the same object. A sound plays across frames, so a block that stopped it on return would stop it within the frame it started; a ParticleSystem or a recording runs across frames likewise. Mounts usually last the whole game, and an attribute stays attached as long as its Mesh lives, so those pairs get no block form until a game needs one. A function kept to call later takes any object that answers `call`, as Ruby's `Signal.trap` does. A setter that keeps a function, such as `setContactFilter` or `setModalDrawCallback`, stores it rather than running it, and a World's `setCallbacks` takes four functions where a method takes one block, so they stay writers; `world.callbacks` returns the four. A callback receives only as many arguments as it declares, as Lota's own callbacks do ([game.md](game.md)).

Rule 30's block runs only on success because `File:open` returns `false`, or `nil` and a message, rather than raising (`wrap_File.cpp`, lines 75–94), and a LÖVE game writes `if file:open("r") then ... file:close() end`.

Rule 13 spells names as Ruby spells its own, as in `use_ssl?` and `sha256`; the V of `VSync` stands for "vertical". A Lua metamethod is a method like any other, and Ruby already names those methods, by their operators where they have one. Rule 13 renames methods only, so enum symbols (rule 9) and record fields (rule 28) keep LÖVE's spelling: `:ETC2rgb`, `:ASTC4x4`.

Rule 14 follows the C++ that produces each number. A resize's size is an Integer while graphics is open because LÖVE then reports the graphics module's int size. An exit status is an Integer because LÖVE's C++ holds it as one.

Rule 41 gives `type` neither meaning on a class that also has `getType`, because there it would be ambiguous in LÖVE itself. A call meant for one then fails loudly instead of answering the other.

Rule 18 names Buffer's class `GraphicsBuffer` because that is the type name LÖVE's `Buffer.cpp` registers, and rule 25 then makes `Buffer` a module, as it makes `Image` one for Texture. Rule 19's `Lota::Object` and `Lota::Data` hide Ruby's classes of the same names inside `Lota`, so Lota's own code writes `::Object` and `::Data` for Ruby's. Rule 20 keeps `clone` because a copy in LÖVE is a copy in Ruby; both `clone` and `dup` make LÖVE's copy through `initialize_copy`. Rule 21 ports LÖVE's LuaJIT code (`wrap_SoundData.lua`, `wrap_ImageData.lua`) rather than the C++ it replaces, because that Lua is what a LÖVE game runs. Rule 22's hooks exist for LÖVE's own Lua wrappers, which Lota replaces.

Rule 23 passes LÖVE's own error messages on with a module's name rewritten by rule 1 and a function's name rewritten to its exact Ruby name, looked up in the binding generator's name table rather than snake-cased, so a Lota developer never meets a `love.` name.

## When no rule fits

When a LÖVE function fits no rule, or two rules at once, nobody decides it case by case. The answer becomes a new rule in this table, and the binding generator (`tasks/bindings/`) applies it everywhere. Collisions are settled at the last responsible moment: `rake bindings:report` lists them all, and each comes to the maintainer when a story first needs one of its functions, not before.

## What never changes

The nouns and primary verbs never change. If LÖVE calls it a SpriteBatch, so does Lota, because a developer looking up an argument searches the LÖVE wiki by LÖVE's name.

Lua tables used as objects become Ruby classes or `Data` in the developer's own code; that is advice for tutorials, not an API rule. Lua's 1-based arrays matter less than they seem, because idiomatic Ruby iterates instead of indexing.

## The literal mode

An optional `require "lota/compat"` adds the literal LÖVE names (`newSpriteBatch`, `setBlendMode`) as aliases of the idiomatic methods, for copying a Lua tutorial verbatim. It also adds a private `Kernel#love` that returns `Lota`, so LÖVE code runs unchanged. AGENTS.md's Trademarks section allows that one identifier because it has to match LÖVE's API. It stays out of the core API, which spells the same thing `lota` ([game.md](game.md)). Lota does not ship `lota/compat` yet.
