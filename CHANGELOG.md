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
- `Lota::Graphics::Texture.new`, translating `love.graphics.newTexture` for one image from a `FileData` or an `ImageData`.
- LÖVE's error messages name Lota's modules and methods (`Lota::Image`, `Lota::Window.set_mode`) where LÖVE's name Lua's (`love.image`, `love.window.setMode`).
- `Lota::Image::ImageData`, decoded from a `Lota::Filesystem::FileData`, with `width`, `height`, and `pixel`.
- `Lota::Filesystem::FileData.new(contents, name)`, translating `love.filesystem.newFileData`.
- `Lota::Graphics` raises `ThreadError` anywhere but the main thread, as LÖVE keeps `love.graphics` there.
- Graphics objects that Ruby's garbage collector frees on another thread are released on the main thread.
- Dependency on SDL3, FreeType, and HarfBuzz, from `love-apple-dependencies`, which `Lota::Native` now loads at run time.
- A precompiled gem for Apple Silicon macOS (platform `arm64-darwin`) and Ruby 4.0, carrying the compiled extension and the frameworks it loads, with their licenses recorded by the REUSE Specification (`REUSE.toml`, and the texts in `LICENSES/`), so `gem install lota` compiles nothing.
- The gem's homepage, source code, and changelog links, pointing at https://github.com/setdef/lota.
- The source gem stops at `gem install` with a message naming the precompiled gem, since it ships no LÖVE sources to build from.
- The `lota` executable: `lota run [path] [arguments]` runs the game in a folder, as `love path/to/game` does.
- A game is a folder of `conf.rb` and `main.rb`; `Lota::Boot` starts it in `boot.lua`'s order, calling `def Lota.conf(t)` with a `Lota::Settings` under LÖVE's names and defaults, which accepts and ignores settings LÖVE does not know; `lota run` puts the folder on `$LOAD_PATH` and leaves the working directory alone.
- `Lota.run`, the game loop translated from `love.run`, calls the callbacks a game defines on `Lota` (`load`, `update`, `draw`, `quit`, `keypressed`, and the rest of LÖVE's), passing each only the arguments it declares and `nil` for a required parameter beyond LÖVE's (an optional one keeps its default), with Integers for the numbers LÖVE holds as integers (a mouse button, a resized window's size) and Floats for the rest; a game can define its own `Lota.run`.
- A private `Kernel#lota` returning `Lota`, and `Lota.filesystem`, `image`, `graphics`, `timer`, `event`, and `window` returning their modules, or `nil` when a module is not open, as when the settings turn it off.
- `Lota::Window.set_mode`, `title=`, and `title`, translating `love.window.setMode`, `setTitle`, and `getTitle`.
- `Lota::Timer.step` and `sleep`, and `Lota::Event.pump` and `quit`, translating `love.timer` and `love.event`.
- `Lota::Graphics.active?`, `origin`, `background_color`, `present`, `width`, `height`, and `dimensions`.
- `Lota::Graphics.rectangle`, `circle`, `ellipse`, `arc`, and `line`, translating `love.graphics.rectangle` (with rounded corners), `circle`, `ellipse`, `arc` (with its `:pie`, `:open`, or `:closed` arc mode), and `line`, in `:fill` or `:line` mode.
- `Lota::Graphics.draw`, translating `love.graphics.draw` for a `Texture` with a position, angle, scale, origin, and shear.
- `Lota::Graphics.color=` and `color`, `line_width=` and `line_width`, and `line_style=` and `line_style`, translating `love.graphics.setColor`, `getColor`, `setLineWidth`, `getLineWidth`, `setLineStyle`, and `getLineStyle`.
- `Lota::Keyboard.down?`, translating `love.keyboard.isDown`, and `Lota.keyboard` returning `Lota::Keyboard`.
- `Lota::Graphics.print` and `printf`, translating `love.graphics.print` and `printf`, which draw a String or colored text with a position, angle, scale, origin, and shear, `printf` wrapped at a limit and aligned `:left`, `:center`, `:right`, or `:justify`.
- `Lota::Graphics::Font.new`, translating `love.graphics.newFont` for LÖVE's default font at a size and for a TrueType font in a `Lota::Filesystem::FileData`, with its hinting and DPI scale after the size or as keywords; and `Lota::Graphics.font=` and `font`, translating `setFont` and `getFont`, which until set is LÖVE's default font, Noto Sans at 13 pixels.
- `Lota::Graphics.default_filter=` and `default_filter`, translating `love.graphics.setDefaultFilter` and `getDefaultFilter`.
- `lota run` opens LÖVE's font module unless `t.modules.font = false`, as `boot.lua` opens `love.font`.
- `Lota::Mouse.system_cursor`, `cursor=`, and `x`, translating `love.mouse.getSystemCursor`, `setCursor`, and `getX`, with `Lota::Mouse::Cursor`; and `Lota.mouse`, opened unless `t.modules.mouse = false`.
- `Lota::Math.random` and `random_seed=`, translating `love.math.random` and `setRandomSeed`, which draw from LÖVE's own generator; and `Lota.math`, opened unless `t.modules.math = false`.
