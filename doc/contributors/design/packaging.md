<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# How a Lota Game Ships

A player who downloads a LÖVE game never meets LÖVE or Lua. The developer "fuses" the game: they join the zipped game onto LÖVE's executable, which is a renamed `.exe` beside its DLLs on Windows, a renamed `.app` with the game inside on macOS, and an AppImage on Linux. At boot LÖVE notices that its own executable carries a game and runs it (`vendor/love/src/modules/love/boot.lua`, lines 76–96).

A Lota game needs more: a Ruby interpreter, Ruby's standard library, the game's gems, Lota's native extension, and LÖVE's engine with its libraries. Almost no player has Ruby. A player of a Lota game still sees exactly what a player of a fused LÖVE game sees: an app to double-click, with nothing to install. Fledge builds that app ([ADR 010](../adr/010.md)). This document says what goes into it and how.

## The runtime

Fledge (github.com/setdef/Fledge) publishes a runtime for each platform: Ruby with its whole standard library and default gems, and a launcher.

- The launcher is a small C program modeled on Ruby's own `main.c`. It embeds CRuby, as LÖVE's executable embeds Lua.
- It sets the player's own Ruby environment aside, so nothing on the player's machine changes the game.
- It runs Ruby on the process's main thread, as the engine needs ([engine.md](engine.md)).
- The standard library ships whole, as LÖVE ships the whole of Lua's, because a game that requires a library and finds it missing is broken. Bundled gems ship only when the game's Gemfile asks for them.
- Fledge chooses where each platform's Ruby comes from (`runtime/sources.yml` in its repository). On Windows it is RubyInstaller's Ruby, built with MinGW against the UCRT ("Windows builds with MinGW", below).

## Platform gems

Lota publishes its native extension as a precompiled gem for each platform, with LÖVE's engine libraries beside it. A native gem has to match the Ruby it loads into, so each Lota gem names the Ruby versions it was built for, and a new Fledge Ruby needs a matching Lota gem first. Lota's continuous integration builds and publishes a gem for every supported platform, so precompiled gems are part of the product. The source gem refuses to build and points to them.

Lota runs on Ruby 4.1, its previews included. `lota.gemspec` asks for `>= 4.1.0.a`, which RubyGems reads as accepting 4.1's previews and refusing 4.0, and each precompiled gem also stops below 4.2 (`tasks/native_gem.rb`). The maintainer chose 4.1 from its previews on 2026-11-09. A player never meets that Ruby, since the app carries Fledge's, and Lota had no outside users to strand. Lota's threads need it: Ruby 4.0 keeps one list for `rb_gc_register_address` that every Ractor changes with no lock, and Rice registers every object it holds there ([engine.md](engine.md), "Threads and Ractors"). So a developer runs `lota run` and `lota fuse` on a 4.1 preview, and each preview, the release candidate, and 4.1.0 need every platform's gem built again. Lota 1.0.0 ships only on Ruby 4.1.0 ([releasing.md](../releasing.md)).

The platforms are:

| RubyGems platform | Machine |
|---|---|
| `arm64-darwin` | Apple Silicon Macs, macOS 15 and newer |
| `x86_64-linux-gnu`, `aarch64-linux-gnu` | Linux with glibc |
| `x64-mingw-ucrt`, `aarch64-mingw-ucrt` | Windows, with RubyInstaller's Ruby |

Intel Macs and musl Linux wait: Fledge builds no Intel Mac runtime, and few players run Alpine.

Phones and tablets are a target: iPhones, iPads, and Android phones and tablets are among the largest places games are played. Fledge links a gem's native extension into its iOS and Android runtimes, and Lota's phone build compiles LÖVE's engine for each iOS slice and Android ABI, against libraries built for each. No Lota gem targets a phone yet, and `lota fuse` builds only for the computer it runs on, so a phone app is built from a clone of Lota, as `doc/guide/phones.md` describes. The app is the Xcode or Gradle project Fledge writes, with Lota's hosts in `ext/lota/phone/host` as its host files, and the developer builds and signs it in their own tools. On iOS, sound plays through Apple's OpenAL framework, as in LÖVE's iOS build, so no LGPL code is in an iOS app. Neither phone restarts a game by `exec`: iOS lets no app run a program, and on Android a process that replaces itself with `exec` is no longer run as the app (Fledge's ADR 082). So `Lota::Event.restart` ends a phone game as a quit does, unless `LOTA_IN_PROCESS_RESTART` asks for a restart in the same process (`lib/lota/restart.rb`), which has not yet run on a phone.

## Windows builds with MinGW

Lota builds LÖVE's engine and its libraries with MinGW, against the UCRT. A native gem has to match the Ruby it loads into, and Fledge's only Windows Ruby is RubyInstaller's, built that way. LÖVE's own Windows builds use Microsoft's compiler, which would need a Ruby built with it, and neither Lota nor Fledge builds one; the maintainer chose MinGW on 2026-11-02. Lota builds the libraries from source at the versions LÖVE builds against, not from MSYS2's newer packages, which keeps OpenAL Soft the only LGPL library in a game. x64 builds with GCC and ARM64 with clang, the toolchains RubyInstaller builds its Ruby with, and no change to LÖVE's source is needed for either.

- The gem carries the compiler's runtime linked in, libstdc++ or libc++, and winpthreads.
- Ruby's MinGW import library exports some of Windows' own functions, such as `Sleep`, under Ruby's DLL. So each extension links kernel32 first, and the gem build refuses a binary that takes a kernel32 function from Ruby, or imports a DLL that is neither the gem's, Ruby's, nor one of Windows' own (`NativeFormat::PE`).
- A build that differs from LÖVE's own can behave differently. [windows.md](../windows.md) says how CI and a Windows PC check it.

## `lota run` and `lota fuse`

During development, `lota run` runs a game on the developer's own Ruby, as `love path/to/game` does ([game.md](game.md)). For release, `lota fuse` turns a game folder into a Fledge project and builds it. It:

- reads the game's name and `t.identity` from `conf.rb`, without opening a window;
- writes a Gemfile that pins `lota` to the running version and Fledge to a release tag (`Lota::Fuse::FLEDGE_REF`); Fledge is not on RubyGems.org, so the Gemfile names it by Git tag, and `lota fuse` needs the network and Git;
- writes an entry script that turns YJIT on where the runtime has it and boots the game as a fused game, `exit Lota::Boot.new(game_dir, ARGV, fused: true).call` (Fledge's launcher does not turn YJIT on);
- writes `fledge.yml`, and copies the game into a folder named for its identity, so a game without `t.identity` does not save under Fledge's `app` folder name ([game.md](game.md));
- never uses the game's `t.version` as the app's version, because `t.version` names the version of LÖVE the game was written for;
- writes the app's notices (below);
- runs `fledge build`, passes `--sign` and Fledge's other signing options along, and prints the paths Fledge reports;
- says that it built the app for this computer's platform only.

Fledge builds an app on a computer of the app's own platform. A developer builds each platform's app on that platform, or on a continuous integration runner for it. One machine does not build for every platform.

A fused game carries a Ruby interpreter, the standard library, and LÖVE's engine, so it is larger than a fused LÖVE game: about 93 MB unpacked on macOS, as a spike measured it before 2026-11-02, with no run cited.

## Signing on macOS

The macOS app is code-signed with the hardened runtime. Ruby's JITs mark memory executable with plain `mprotect` rather than `MAP_JIT`, so Fledge's signature carries `com.apple.security.cs.allow-unsigned-executable-memory` and `com.apple.security.cs.disable-library-validation`. LÖVE's own macOS build already declares the first (`vendor/love/platform/xcode/love.entitlements`). YJIT runs under both, signed ad hoc. Whether notarization accepts them under a Developer ID signature is confirmed when Lota first signs one.

Under the macOS App Sandbox, a fused game runs with YJIT on and no entitlement but `com.apple.security.app-sandbox`, and saves inside its container, as a sandboxed LÖVE game does. On macOS 15 the sandbox kills a restart, since it uses `exec` ([game.md](game.md), "Restarting"). Fledge does not add the sandbox entitlement: it builds for Developer ID, not for the Mac App Store.

## Licenses and notices

Lota is AGPL-3.0-or-later; LÖVE's Zlib license permits that. A fused game ships Lota itself, and with it Lota's license, so a developer who distributes a game offers Lota's Corresponding Source. Fledge is MIT-licensed, and asks only that its notices stay in the app.

`lota fuse` writes `NOTICES.txt` from the gem the app ships: Lota's own license statement, then each library that gem carries, with its licenses and copyright notices, and the text of each license. No option changes it.

- OpenAL Soft is LGPL, so it ships as a separate library a player can replace, with its source archive inside the app.
- FreeType's license asks for a credit in a product's documentation, so the notices carry one.
