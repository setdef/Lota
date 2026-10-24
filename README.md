<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Lota

Lota lets you make 2D games in Ruby on the engine [LÖVE](https://love2d.org) games run on. It drives LÖVE's own C++ engine from Ruby instead of Lua, so a game behaves the same in both, and a LÖVE tutorial still reads true once its calls are translated by a handful of rules.

Lota is a plan, not yet a gem you can install. Contributors start with [ADR 001](doc/contributors/adr/001.md), which records what Lota is and why, and [Plan 001](doc/contributors/plan/001.md), which orders the work.

## Development

Clone with submodules. `vendor/love` holds the LÖVE source Lota builds against, and `vendor/love-apple-dependencies` holds the prebuilt libraries LÖVE links on macOS (SDL3, FreeType, HarfBuzz, OpenAL Soft, and the rest):

```bash
git clone --recurse-submodules <repository>
bin/setup
bundle exec rake
```

`bin/setup` installs the pinned tools from `mise.toml`, CMake, Ninja, clang-format, and clang-tidy among them. `bundle exec rake` builds LÖVE's engine as a static library into `tmp/engine/build`, then runs the C++ gates over Lota's own C++ in `ext/`. To work on the native side alone:

- `bundle exec rake engine` builds the engine. A clean build takes under a minute; a rebuild with no changes takes a second or two.
- `bundle exec rake engine:sources` regenerates `ext/lota/engine/sources_macos.cmake`, the list of LÖVE sources the engine compiles, after a bump of `vendor/love`. `rake engine:sources:check` fails until you do, so review the difference before you commit it.
- `bundle exec rake cpp` runs `cpp:format`, `cpp:no_nolint`, and `cpp:tidy`; `rake cpp:format:fix` rewrites the layout clang-format reports.

## Copyright & License

Lota is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](vendor/love/license.txt).
