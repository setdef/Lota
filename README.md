<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Lota

Lota lets you make 2D games in Ruby on the engine [LÖVE](https://love2d.org) games run on. It drives LÖVE's own C++ engine from Ruby instead of Lua, so a game behaves the same in both, and a LÖVE tutorial still reads true once its calls are translated by a handful of rules.

Lota is a plan, not yet a gem you can install. Contributors start with [ADR 001](doc/contributors/adr/001.md), which records what Lota is and why, and [Plan 001](doc/contributors/plan/001.md), which orders the work.

## Development

Clone with submodules, since `vendor/love` holds the LÖVE source Lota builds against:

```bash
git clone --recurse-submodules <repository>
bin/setup
bundle exec rake
```

## Copyright & License

Lota is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](vendor/love/license.txt).
