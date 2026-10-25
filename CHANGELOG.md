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
- Dependency on `rice` 4.12.0, whose headers the extension compiles against.
- `Lota::Graphics::Canvas.new`, `Lota::Graphics.canvas=`, `Lota::Graphics.clear`, and `Lota::Graphics.readback_texture`, translating `love.graphics.newCanvas`, `setCanvas`, `clear`, and `readbackTexture`.
- `Lota::Image::ImageData`, decoded from a `Lota::Filesystem::FileData`, with `width`, `height`, and `pixel`.
- `Lota::Filesystem::FileData.new(contents, name)`, translating `love.filesystem.newFileData`.
- `Lota::Graphics` raises `ThreadError` anywhere but the main thread, as LÖVE keeps `love.graphics` there.
- Graphics objects that Ruby's garbage collector frees on another thread are released on the main thread.
- Dependency on SDL3, from `love-apple-dependencies`, which `Lota::Native` now loads at run time.
