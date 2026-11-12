<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Sharing a Game

A player should not need Ruby, Lota, or a terminal to play your game. `lota fuse` builds the game into an app they download and run, as LÖVE fuses a game into an executable of its own. It hands the game to [Fledge](https://github.com/setdef/Fledge), which packages a Ruby program with a Ruby of its own. This page covers what it writes, what it needs, every option, and how it treats your files and your gems.

## The command

Run it in the game's folder, or name the folder:

```console
$ lota fuse path/to/game --identifier com.example.SampleGame
dist/Sample Game-x64-mingw-ucrt.zip
dist/Sample Game-x64-mingw-ucrt-setup.exe
Built the app for x64-mingw-ucrt only. Run lota fuse on each platform you ship for.
```

## What a player gets

Fledge builds for the computer it runs on, so build each platform's app on that platform: on a Mac for macOS, on Windows for Windows, on Linux for Linux. A player gets:

| Platform | What `lota fuse` writes in `dist` |
| --- | --- |
| macOS | `NAME.app`, in a `.tar.gz` and a `.dmg` |
| Windows | `NAME.exe` and what it needs, in a `.zip`, and a `-setup.exe` that installs it without an administrator |
| Linux | A folder with `NAME` and a desktop entry, in a `.tar.gz`, and an AppImage (glibc 2.39 or newer: Ubuntu 24.04, Debian 13) |

The app's name is `conf.rb`'s `t.window.title`, or else `t.title`, or else the game folder's name. It saves under `t.identity`, or under the game folder's name, as `lota run` does. `lota fuse` writes the project it builds from in `dist/fuse-project`, and the game goes in it under `game/<identity>`. Fledge runs from a Gemfile of its own beside it, in `dist/fuse-tools`, so it is none of the app's gems.

## What you need

To fuse a game, you need:

- Lota's gem for your platform, installed from the release, as [the README](../../README.md#installation) shows. `lota fuse` puts that very gem file in the app, unless your game's `vendor/cache` holds it.
- Ruby 4.0, which the app gets a copy of: on Windows, [RubyInstaller](https://rubyinstaller.org/)'s Ruby 4.0 for x64 or ARM64. Its MSYS2 tools are needed only for a gem that compiles ([Your gems](#your-gems)).
- Git, and the network: Fledge is not on RubyGems.org, so Bundler fetches it from GitHub, and Fledge downloads its runtime for your platform the first time. On Windows, install [Git for Windows](https://git-scm.com/download/win); on a Mac, `xcode-select --install` installs Git. Fledge carries what it builds installers with, NSIS among them.

## Options

The options:

- `--identifier ID` is the reverse-DNS name macOS and Windows know the app by, such as `com.example.SampleGame`. Without it the app gets `com.example.<identity>`, a placeholder: replace it before you ship.
- `--app-version VERSION` is the app's version, such as `1.0.0`; without it, Fledge's `0.0.0`. A game's `t.version` names the version of LÖVE it was written for, so it never becomes the app's.
- `--icon PATH` gives the app the icon files at `PATH` in the game's folder, without their extension, as Fledge takes them: `--icon icons/icon` for `icons/icon.icns` (macOS), `icons/icon.ico` (Windows), and `icons/icon-16.png` to `icons/icon-512.png` (Linux). Without it the app has no icon of its own.
- `--sign IDENTITY` signs the app, as Fledge's `--sign` does: a signing identity from your keychain on macOS, a certificate's SHA-1 thumbprint on Windows. Unsigned, Gatekeeper and SmartScreen warn the people who download it.
- `--sign-command COMMAND` signs a Windows app with a command of your own instead, as Fledge's `--sign-command` does, for a certificate kept in a cloud or hardware service: Fledge runs `COMMAND` through `cmd.exe` for each program and library, the uninstaller, and the setup program, with the file's path in place of `%1`, or after `COMMAND` if it has no `%1`. Given neither option on Windows, Fledge takes the command from `FLEDGE_SIGN_COMMAND`.
- `--notarize PROFILE` has Apple notarize the macOS app that `--sign` signed with a Developer ID Application identity, and staples Apple's ticket to it, as Fledge's `--notarize` does, with the credentials that `xcrun notarytool store-credentials PROFILE` stored in your keychain. It waits for Apple, usually minutes.
- `--exclude PATTERN` leaves paths out of the app; see [Leaving files out](#leaving-files-out). Give it as often as you like.
- `--out DIR` writes to `DIR` instead of `dist`.
- `LOTA_FLEDGE_REF` names another tag or commit of Fledge to build with.

`--sign` and `--sign-command` together, or `--notarize` without `--sign`, stop `lota fuse` before it writes anything. Fledge refuses `--sign-command` on any system but Windows, `--notarize` on any but macOS or with the ad hoc identity `-`, and an app Apple will not notarize, and `lota fuse` stops after Fledge says why.

## Leaving files out

The app holds your game's folder as it is, but for `.git`, `.bundle`, `vendor/bundle`, and `vendor/cache`, which it always leaves out. To leave out more, such as a server's code, your tests, and your docs, give `--exclude` a pattern for each:

```console
$ lota fuse path/to/game --exclude server --exclude 'test/**' --exclude doc
dist/Sample Game-x64-mingw-ucrt.zip
Left out 3 paths of the game: doc, server, test/a_test.rb
Built the app for x64-mingw-ucrt only. Run lota fuse on each platform you ship for.
```

A pattern is a glob relative to the game's folder, matched as Ruby's `File.fnmatch` does with `FNM_PATHNAME`, `FNM_EXTGLOB`, and `FNM_DOTMATCH`. So `*` stays within a folder, `**/` crosses folders (`**/*.psd`), `{a,b}` picks one of two (`*.{psd,xcf}`), and `*` matches dotfiles too, because someone who writes `assets/*` means the `.DS_Store` in it. Quote a pattern with a star, so your shell hands it to `lota fuse` as written. A path that matches is left out whole: `server` leaves out the folder `server` at the top of the game, with everything in it, but not `lib/server`. A pattern that ends in a slash (`doc/`) matches folders only. `test/**` is everything in `test`, as `fnmatch` reads it, so it leaves an empty `test` folder. `lota fuse` reads no file of patterns, and it prints the paths it left out. A pattern that matches nothing is reported, but does not stop the build. One that would leave out `conf.rb` or `main.rb`, which the game needs to start, stops it before it writes anything, as every error of `lota fuse` does, with exit status 1.

## Your gems

If your game has a `Gemfile`, the app ships the gems its `Gemfile.lock` locks, at the versions it locks, but for the `development` and `test` groups. `lota fuse` builds from your Gemfile and lockfile, and adds Lota if your Gemfile does not ask for it. Before it builds, it checks that:

- a `Gemfile.lock` is beside the `Gemfile`. Run `bundle install` in the game's folder to write one.
- the lockfile locks the platform you build on. Run `bundle lock --add-platform x64-mingw-ucrt` (or your platform) in the game's folder; a gem that only `vendor/cache` holds, such as Lota, needs that platform's `.gem` file there first.
- the lockfile locks this version of Lota, if it locks Lota at all.

Gems come from where your lockfile says: RubyGems.org, Git, a folder inside the game, or the game's `vendor/cache`, whose gems for other platforms stay out of the app. Bundler only locks them; it installs none. Fledge fetches each gem the app ships and checks it against your lockfile's checksum. A shipped gem with a C extension and no build for your platform compiles once, on your computer, for the app's Ruby. A gem in the `development` or `test` group never compiles, so a game whose shipped gems are all pure Ruby or precompiled fuses without a C compiler. Any other needs one: on macOS, Xcode's command line tools (`xcode-select --install`); on Linux, a C compiler and `make` (`sudo apt install build-essential` on Debian and Ubuntu); on Windows, RubyInstaller's MSYS2 tools (`ridk install`). Without one, `lota fuse` stops after the compiler's output names the gem that failed, and says what to install. An extension compiles for the computer it compiles on, which is one more reason to build each platform's app on that platform.

Your other gems go into the app whole, with the license files their packages hold, whatever their licenses. What those licenses ask of you when you give the app to people is yours to honor, as with any Ruby program you ship: `bundle licenses` lists the license each gem declares, and a gem whose package leaves out its license text, which a license such as MIT asks you to keep with every copy, needs it added to the notices you ship.

## Notices

Every app carries a notices file, `app/NOTICES.txt`, in the folder beside the app's program (in `NAME.app/Contents/Resources` on macOS). It states Lota's license, AGPL-3.0-or-later, and names each library Lota's gem for that platform carries, compiled into Lota's extension or beside it, with its version where it is known, its licenses, and its notices of copyright. It gives FreeType's credit in the words FreeType's license asks for, says where OpenAL Soft's source archive is in the app, and ends with the text of each license it names. `lota fuse` writes it on every build from the very gem the app ships, and stops on a Lota gem that does not carry what it needs. Fledge's own `notices/NOTICES.txt`, beside it, covers Ruby and the rest of the runtime.

## Restarting, and what is missing

A fused game restarts as LÖVE's does: `Lota::Event.restart` ends it, and the app's program starts it again with the same arguments, with `Lota.restart` holding the value, as `lota run` and `bundle exec lota run` do.

What a fused game does not do yet: `lota fuse` builds no phone app; [the phone guide](phones.md) builds one with Fledge directly, or with the iOS kit from your game's CI. On Windows the app opens no console, so what the game prints goes nowhere, and Ruby's YJIT is not in RubyInstaller's Ruby, so a Windows app runs without it; elsewhere the app turns YJIT on.
