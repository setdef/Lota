<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Lota

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

Lota lets you make 2D games in Ruby on the engine [LÖVE](https://love2d.org) games run on. It drives LÖVE's own C++ engine from Ruby instead of Lua, so a game behaves the same in both, and a LÖVE tutorial still reads true once its calls are translated by a handful of rules.

Lota is a plan, not yet a gem you can install. Contributors start with [ADR 001](doc/contributors/adr/001.md), which records what Lota is and why, and [Plan 001](doc/contributors/plan/001.md), which orders the work.

## Development

Clone with submodules. `vendor/love` holds the LÖVE source Lota builds against, and `vendor/love-apple-dependencies` holds the prebuilt libraries LÖVE links on macOS (SDL3, FreeType, HarfBuzz, OpenAL Soft, and the rest):

```bash
git clone --recurse-submodules <repository>
bin/setup
bundle exec rake
```

`bin/setup` installs the pinned tools from `mise.toml`, CMake, Ninja, clang-format, and clang-tidy among them. `bundle exec rake` builds LÖVE's engine and the `Lota::Native` extension into `tmp/engine/build`, runs the tests (the native ones a second time under AddressSanitizer and UndefinedBehaviorSanitizer), then runs the C++ gates over Lota's own C++ in `ext/`. A clean run takes about four minutes, most of it compiling the engine twice; a run with nothing to rebuild takes under a minute. To work on the native side alone:

- `bundle exec rake compile` builds the engine and the extensions and copies `Lota::Native` to `lib/lota/native.bundle`. rake-compiler runs `ext/lota/extconf.rb`, which configures the CMake project in `ext/lota` and writes a Makefile that builds it; `gem install` runs the same script. CMake decides what to rebuild, so `rake compile` always calls it, and a build with no changes takes a second or two.
- `bundle exec rake test:native` rebuilds everything with ASan and UBSan into `tmp/sanitize/build` and runs `test/native` and `test/sanitizers` against it. ASan has to be in the Ruby process before anything it instruments, so the task starts Ruby directly with `DYLD_INSERT_LIBRARIES`; a shell or a binstub in between would drop it, because macOS removes `DYLD_` variables when it starts a protected binary such as `/bin/sh`. `test/sanitizers` holds deliberate memory bugs, and only this task runs it.
- `bundle exec rake engine:sources` regenerates `ext/lota/engine/sources_macos.cmake`, the list of LÖVE sources the engine compiles, after a bump of `vendor/love`. `rake engine:sources:check` fails until you do, so review the difference before you commit it.
- `bundle exec rake cpp` runs `cpp:format`, `cpp:no_nolint`, and `cpp:tidy`; `rake cpp:format:fix` rewrites the layout clang-format reports.

Bindings live in `ext/lota/native`. Each one includes `native/binding.hpp`, never Rice's own header, because `binding.hpp` is where every `love::Object` gets LÖVE's memory model (ADR 001, section 5): a Ruby wrapper holds one reference from the moment Ruby wraps the object until the garbage collector frees the wrapper. `ext/lota/native_test` is a test-only extension, `LotaNativeTest`, that the tests load from the build tree; the gem never packages it. `Lota::Native` has no RBS generator yet, so its signatures in `sig/lota/native.rbs` are written by hand, and `rbs:parity` checks them against the compiled extension.

## Copyright & License

Lota is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), and the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt). LÖVE is [Zlib](vendor/love/license.txt).
