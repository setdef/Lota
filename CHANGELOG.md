<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Lota::Native`, the compiled extension that binds LÖVE's engine, with `Lota::Native::RandomGenerator`.
- `Lota::Graphics::Canvas.new`, `Lota::Graphics.canvas=`, `Lota::Graphics.clear`, and `Lota::Graphics.readback_texture`, translating `love.graphics.newCanvas` (with its `msaa:` setting), `setCanvas`, `clear`, and `readbackTexture`.
- `Lota::Graphics::Texture`, with `canvas?`; `Canvas.new` returns a `Texture`, as LÖVE 12's `newCanvas` does, and `Canvas === texture` asks `texture.canvas?`.
- `Lota::Graphics::Texture.new`, translating `love.graphics.newTexture` for one image from a file name, a `FileData`, or an `ImageData`, with its `canvas:` setting.
- `Lota::Graphics::Image.new`, translating `love.graphics.newImage`, which in LÖVE 12 is `newTexture`; `Image === x` is true for any `Texture`, canvases included.
- LÖVE's error messages name Lota's modules and methods (`Lota::Image`, `Lota::Window.set_mode`, `Lota::Image::ImageData#pixel`) where LÖVE's name Lua's (`love.image`, `love.window.setMode`, `ImageData:getPixel`), each method by the exact name ADR 001's rules give it.
- `Lota::Image::ImageData`, decoded from a `Lota::Filesystem::FileData` or a file name, with `width`, `height`, and `pixel`.
- `Lota::Filesystem::FileData.new(contents, name)`, translating `love.filesystem.newFileData`.
- `Lota::Graphics` raises `ThreadError` anywhere but the main thread, as LÖVE keeps `love.graphics` there.
- Graphics objects that Ruby's garbage collector frees on another thread are released on the main thread.
- Dependency on SDL3, FreeType, and HarfBuzz, from `love-apple-dependencies`, which `Lota::Native` now loads at run time.
- A precompiled gem for Apple Silicon macOS (platform `arm64-darwin`) and Ruby 4.0, carrying the compiled extension and the frameworks it loads, with their licenses recorded by the REUSE Specification (`REUSE.toml`, and the texts in `LICENSES/`), so `gem install lota` compiles nothing.
- The gem's homepage, source code, and changelog links, pointing at https://github.com/setdef/lota.
- The source gem stops at `gem install` with a message naming the precompiled gem, since it ships no LÖVE sources to build from.
- The `lota` executable: `lota run [path] [arguments]` runs the game in a folder, as `love path/to/game` does.
- A game is a folder of `conf.rb` and `main.rb`; `Lota::Boot` starts it in `boot.lua`'s order, calling `def Lota.conf(t)` with a `Lota::Settings` under LÖVE's names and defaults, which accepts and ignores settings LÖVE does not know and reads a setting never set as `nil`; `lota run` puts the folder on `$LOAD_PATH` and leaves the working directory alone.
- `Lota.run`, the game loop translated from `love.run`, calls the callbacks a game defines on `Lota` (`load`, `update`, `draw`, `quit`, `keypressed`, and the rest of LÖVE's), passing each only the arguments it declares and `nil` for a required parameter beyond LÖVE's (an optional one keeps its default), with Integers for the numbers LÖVE holds as integers (a mouse button, a resized window's size) and Floats for the rest; a game can define its own `Lota.run`.
- A private `Kernel#lota` returning `Lota`, and `Lota.filesystem`, `image`, `graphics`, `timer`, `event`, and `window` returning their modules, or `nil` when a module is not open, as when the settings turn it off.
- `Lota::Window.set_mode`, `title=`, and `title`, translating `love.window.setMode`, `setTitle`, and `getTitle`.
- `Lota::Timer.step` and `sleep`, and `Lota::Event.pump` and `quit`, translating `love.timer` and `love.event`; a quit's exit status leaves the event queue as an Integer, so `Lota::Event.quit(3)` exits with 3.
- `Lota::Graphics.active?`, `origin`, `background_color`, `present`, `width`, `height`, and `dimensions`.
- `Lota::Graphics.rectangle`, `circle`, `ellipse`, `arc`, and `line`, translating `love.graphics.rectangle` (with rounded corners), `circle`, `ellipse`, `arc` (with its `:pie`, `:open`, or `:closed` arc mode), and `line`, in `:fill` or `:line` mode.
- `Lota::Graphics.draw`, translating `love.graphics.draw` for a `Texture`, a `Texture` through a `Quad`, or a `SpriteBatch`, with a position, angle, scale, origin, and shear.
- `Lota::Graphics::Quad.new`, translating `love.graphics.newQuad` with a texture or its size and an optional layer, with `viewport`, `viewport=`, `texture_dimensions`, `layer`, and `layer=`.
- `Lota::Graphics::SpriteBatch.new`, translating `love.graphics.newSpriteBatch` with its size and usage hint, with `add`, `set`, `clear`, `flush`, `texture`, `texture=`, `color`, `color=`, `count`, `buffer_size`, `draw_range`, and `draw_range=` (`nil` draws every sprite again); `draw_range` is `[]` while every sprite is drawn, as every function with several results returns an Array of all it returns.
- `Lota::Graphics::Texture#width`, `#height`, and `#dimensions`, translating `Texture:getWidth`, `getHeight`, and `getDimensions`, of the first mipmap or the one given; and `#render_to`, translating `Texture:renderTo`, whose function becomes a block, putting back the canvas set before even when the block raises.
- `lota run` checks `t.version` as `boot.lua` does: a version the engine is not compatible with prints LÖVE's warning and shows it in a dialog before the window opens.
- `Lota::Graphics.color=` and `color`, `line_width=` and `line_width`, and `line_style=` and `line_style`, translating `love.graphics.setColor`, `getColor`, `setLineWidth`, `getLineWidth`, `setLineStyle`, and `getLineStyle`.
- `Lota::Keyboard.down?`, translating `love.keyboard.isDown`, and `Lota.keyboard` returning `Lota::Keyboard`.
- `Lota::Graphics.print` and `printf`, translating `love.graphics.print` and `printf`, which draw a String or colored text with a position, angle, scale, origin, and shear, `printf` wrapped at a limit and aligned `:left`, `:center`, `:right`, or `:justify`, in the current font or a `Font` given before the position.
- `Lota::Graphics::Font.new`, translating `love.graphics.newFont` for LÖVE's default font at a size and for a TrueType font in a file or a `Lota::Filesystem::FileData`, with its hinting and DPI scale after the size or as keywords; and `Lota::Graphics.font=` and `font`, translating `setFont` and `getFont`, which until set is LÖVE's default font, Noto Sans at 13 pixels.
- `Lota::Graphics.default_filter=` and `default_filter`, translating `love.graphics.setDefaultFilter` and `getDefaultFilter`.
- `lota run` opens LÖVE's font module unless `t.modules.font = false`, as `boot.lua` opens `love.font`.
- `lota run` opens LÖVE's filesystem with the game's folder as its source, as `boot.lua` does, so a file name a game passes is read from its folder, and names its save directory after the folder, then after `t.identity` (with `t.appendidentity`).
- A game saves in the system's application data folder (on macOS, `~/Library/Application Support`), in a `Lota` folder under its identity, where LÖVE's saves in a `LOVE` one; a fused game, which `Lota::Boot.new(path, fused: true)` starts, saves under its identity alone, where LÖVE's fused game does.
- `Lota::Filesystem.identity=`, `identity`, `save_directory`, `fused?`, `fused=`, `create_directory`, `remove`, and `lines`, translating `love.filesystem.setIdentity`, `getIdentity`, `getSaveDirectory`, `isFused`, `setFused`, `createDirectory`, `remove`, and `lines`, whose iterator becomes an Enumerator.
- `Lota::Audio::Source.new`, translating `love.audio.newSource` with a file name and `:static` or `:stream`, with `play`, `stop`, `pause`, `playing?`, `pitch`, `pitch=`, `volume`, `volume=`, `looping?`, `looping=`, and `channel_count`; `Lota::Audio.play`, `stop`, `volume`, `volume=`, and `active_source_count`; and `Lota.audio` and `Lota.sound`, opened unless the settings turn them off, falling back to LÖVE's silent audio module, as LÖVE does, when OpenAL cannot open a device.
- `Lota::Mouse.y`, `position`, `x=`, `y=`, `position=`, and `down?`, translating `love.mouse.getY`, `getPosition`, `setX`, `setY`, `setPosition`, and `isDown`; and `Lota::Timer.delta`, translating `love.timer.getDelta`.
- Dependency on libvorbis, libogg, and libmodplug, from `love-apple-dependencies`, which the precompiled gem now carries, and on OpenAL Soft 1.24.3, which the precompiled gem carries as a framework of its own, a player can replace, with the release's source archive in `sources/` and its licenses recorded, as its license, the GNU Library General Public License, asks.
- `Lota::Mouse.system_cursor`, `cursor=`, and `x`, translating `love.mouse.getSystemCursor`, `setCursor`, and `getX`, with `Lota::Mouse::Cursor`; and `Lota.mouse`, opened unless `t.modules.mouse = false`.
- `Lota::Math.random` and `random_seed=`, translating `love.math.random` and `setRandomSeed`, which draw from LÖVE's own generator; and `Lota.math`, opened unless `t.modules.math = false`.
- `Lota::Event.poll`, translating `love.event.poll`, as an Enumerator of each queued message's name and arguments that also takes a block; and `Lota::Event.push` and `clear`.
- `Lota::Object`, included by every engine object (`Texture`, `Font`, `ImageData`, `FileData`, `Cursor`), with `type` and `type_of?`, translating `Object:type` and `Object:typeOf`, with LÖVE's type names and parents.
- `Lota::Font` and `Lota.font`, for LÖVE's font module, `nil` when `t.modules.font = false`.
- `Lota::System.clipboard_text=` and `clipboard_text`, translating `love.system.setClipboardText` and `getClipboardText`, and `Lota.system`; `lota run` opens the system module before `conf.rb`, as `boot.lua` does.
- LÖVE's error screen: an error a game raises prints the error and its Ruby backtrace and shows them in the game's window, as `love.errorhandler` does, until the player presses Escape or quits; Ctrl+C copies them. A game may define `Lota.errorhandler` to replace it; `Lota.errhand` is another name for the default handler.
- `Lota::Filesystem.info`, `read`, and `write`, translating `love.filesystem.getInfo`, `read`, and `write`: `info` returns a frozen `Lota::Filesystem::Info` with LÖVE's fields (`type`, `readonly`, `size`, `modtime`) or `nil`, and takes LÖVE's file type filter; `read` returns `[contents, size]`, and `write` `[true]`, or either `[nil, message]` when the file cannot be read or written.
- `Lota::Graphics.push`, which also takes a block and pops after it, `pop`, `translate`, `scale`, and `shear`, translating `love.graphics.push`, `pop`, `translate`, `scale`, and `shear`.
- `Lota::Window.update_mode`, `mode`, `desktop_dimensions`, and `safe_area`, translating `love.window.updateMode`, `getMode`, `getDesktopDimensions`, and `getSafeArea`; `mode` returns the width, the height, and a frozen `Lota::Window::Mode` of the settings, with LÖVE's field names.
- `Lota::System.os`, translating `love.system.getOS`.
- `Lota::Mouse.visible=`, `visible?`, `grabbed=`, `grabbed?`, `set_relative_mode`, `relative_mode`, and `cursor_supported?`; `Lota::Graphics.created?` and `reset`; and `Lota::Window.open?`.
- `Lota::Sound::SoundData.new` and `Lota::Sound::Decoder.new`, translating `love.sound.newSoundData` (from a file, a `FileData`, a `Decoder`, or a sample count, rate, bit depth, and channel count) and `love.sound.newDecoder` (from a file with `:file` or `:memory`, or a `FileData`).
- `Lota::Sound::SoundData#channel_count`, `bit_depth`, `sample_rate`, `sample_count`, `duration`, `sample`, `sample=`, `copy_from`, and `slice`; `sample` and `sample=` read and store as LÖVE's LuaJIT code does, in double precision.
- `Lota::Data`, LÖVE's root type Data, which `SoundData`, `ImageData`, and `FileData` include, with `size`, `string`, `perform_atomic` (whose function is a block), `float`, `double`, `int8`, `int16`, and `int32`, translating Data's `getSize`, `getString`, `performAtomic`, `getFloat`, `getDouble`, `getInt8`, `getInt16`, and `getInt32`.
- `clone` and `dup` make LÖVE's copy of a `SoundData`, `Decoder`, `ImageData`, `FileData`, or `Lota::Audio::Source`, translating each one's `clone`.
- `Lota::Image::ImageData.new(width, height, format = :rgba8, rawdata = nil)`, `#pixel=`, and `#map_pixel`, translating `love.image.newImageData` with a size, `ImageData:setPixel`, and `ImageData:mapPixel`, whose function is a block; `#pixel` now reads as LÖVE's LuaJIT code does, in double precision and with its position rounded down, as do `#pixel=` and `#map_pixel`.
- `Lota::Native::RandomGenerator#random_normal` takes a mean after the standard deviation.
- `Lota::Physics` and `Lota.physics`, translating love.physics, which `lota run` opens unless `t.modules.physics = false`: `World`, `Body`, `Shape` with `CircleShape`, `PolygonShape`, `EdgeShape`, and `ChainShape`, `RectangleShape.new`, eleven `Joint` classes from `DistanceJoint` to `WheelJoint`, and `Contact`, with the methods Lövetest's physics tests call, `meter`, `meter=`, and `distance`; `World#query_shapes_in_area` and `#ray_cast` take blocks, and an engine object read back twice is the same Ruby object. `World#set_callbacks` and the contact filter, and `getType` of a Body, Shape, or Joint, are not translated yet.
- Dependency on Box2D 2.4, which LÖVE bundles, now linked into `Lota::Native` with LÖVE's physics module, which Lota changes with a patch of its own (`ext/lota/engine/physics.patch`).
- `Lota::Sound::Decoder#decode`, `channel_count`, `bit_depth`, `sample_rate`, and `duration`.
