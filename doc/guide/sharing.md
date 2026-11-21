<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Sharing a Game

A player should not need Ruby, Lota, or a terminal to play your game. `lota fuse` builds the game into an app they download and run, as LÖVE fuses a game into an executable of its own. It hands the game to [Fledge](https://github.com/setdef/Fledge), which packages a Ruby program with a Ruby of its own. This page covers what it writes, what it needs, every option, and how it treats your files and your gems, then how to hand your game, as one file, to someone who has Lota, how the fuser makes that file into an app with no terminal, and where a fused game's output goes.

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
- Ruby 4.1, as [the README](../../README.md#compatibility) says, a preview until Ruby 4.1.0 is released. The app carries Fledge's own copy of Ruby 4.1, not yours. On Windows, that is the head build of [RubyInstaller](https://rubyinstaller.org/) that Fledge keeps, for x64 or ARM64, which loads zlib from MSYS2, so until RubyInstaller releases Ruby 4.1 you need its MSYS2 tools (`ridk install`) to fuse any game, set up as [Making a game on Windows](windows.md) shows; with a released RubyInstaller, they are needed only for a gem that compiles ([Your gems](#your-gems)).
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

`lota fuse` leaves out nothing else on its own, so the app carries your dotfiles and your tools' files too: `.gitignore`, `.gitattributes`, an editor's settings, mise's `mise.local.toml`. Name each with `--exclude`, and look in `dist/fuse-project/game` after a build to see what went in. Keep one of them: the file your Gemfile's `ruby file:` line names, such as `.ruby-version`, `.tool-versions`, or `mise.toml`. Bundler reads it as `lota fuse` locks the game's gems, so a pattern that would leave it out, or the folder it is in, stops the build before it writes anything, as one that names `main.rb` does.

## Your gems

If your game has a `Gemfile`, the app ships the gems its `Gemfile.lock` locks, at the versions it locks, but for the `development` and `test` groups and any group Bundler's `without` setting leaves out. To ship one of them, name it in Bundler's `with` in the game's folder, as in `bundle config set --local with development`. `lota fuse` reads both settings as Bundler reads them there: from the game's `.bundle/config`, then `BUNDLE_WITH` and `BUNDLE_WITHOUT`, then your own. It builds from your Gemfile and lockfile, and adds Lota if your Gemfile does not ask for it. Before it builds, it checks that:

- a `Gemfile.lock` is beside the `Gemfile`. Run `bundle install` in the game's folder to write one.
- the lockfile locks the platform you build on. Run `bundle lock --add-platform x64-mingw-ucrt` (or your platform) in the game's folder; a gem that only `vendor/cache` holds, such as Lota, needs that platform's `.gem` file there first.
- the lockfile locks this version of Lota, if it locks Lota at all.

Fledge then checks that your Gemfile's `ruby` line, if it has one, admits the Ruby of Fledge's runtime for your platform, as RubyGems names it. Fledge v0.14.0, the Fledge `lota fuse` builds with today, names that Ruby 4.1.0.preview1 on macOS and Linux, and 4.1.0.dev on Windows, where its Ruby is RubyInstaller's head build. So a line that asks for the preview exactly, such as `ruby file: ".ruby-version"` with a `.ruby-version` that says `4.1.0-preview1`, fuses on macOS and Linux but not on Windows. There `bundle exec` refuses it ([Making a game on Windows](windows.md#install-lota-and-run-a-game)), and `lota fuse` stops after Fledge says `Bundler is unlocking ruby, but the lockfile can't be updated because frozen mode is set`. For a game you build on every platform, ask for any Ruby 4.1 instead:

```ruby
# Gemfile
ruby "< 4.2", ">= 4.1.0.a"
```

`4.1.0.a` sorts before every preview of 4.1.0, so the line admits the preview on macOS and Linux, the head build on Windows, Fledge's runtimes, and every release of Ruby 4.1, and it keeps working when Ruby 4.1.0 is released. An upper bound of `<= 4.1.0` would stop at 4.1.1. On 2026-11-20, with Fledge v0.14.0 and Lota's Ruby on macOS, Linux, and Windows, a game with this line fused, and so did one with its bounds the other way round, `ruby ">= 4.1.0.a", "< 4.2"`, whether its lockfile's `BUNDLED WITH` named Bundler 4.1 or Bundler 4.0. Read this paragraph again when Lota moves to a newer Fledge.

Gems come from where your lockfile says: RubyGems.org, Git, a folder inside the game, or the game's `vendor/cache`, whose gems for other platforms stay out of the app. Bundler only locks them; it installs none. Fledge fetches each gem the app ships and checks it against your lockfile's checksum.

Bundler is one of those gems when the app runs a Bundler other than its runtime's own. The app runs the Bundler that the lockfile's `BUNDLED WITH` names, as `bundle exec` does, and `lota fuse` writes that line as it locks the project, naming the Bundler it runs. That is the one `bundle` runs in your game's folder: the one your lockfile names, if your Ruby has it, or else your Ruby's newest. The folder you run `lota fuse` from, and any lockfile there, change nothing. A Ruby's own Bundler writes no checksum of itself, since it has no `.gem` file to hash. So if the two differ, Fledge stops with `Gemfile.lock has no checksum for bundler (VERSION)`, and says what to run. Install that version of Bundler as a gem and add the checksums, in the game's folder, then fuse again:

```console
$ gem install bundler -v VERSION
$ bundle lock --add-checksums
```

The lockfile then lists `bundler (VERSION)` in its `CHECKSUMS`, and `bundle exec` and `lota fuse` take it, on macOS, Linux, and Windows, where it was tried. A Bundler you installed as a gem writes that line when it locks. On 2026-11-20, with Lota's Ruby on all three and Fledge v0.14.0, a game whose lockfile a Ruby's own Bundler had written needed no such line: `lota fuse` locked it with the Bundler of Fledge's runtime for that platform, even from a lockfile that a Mac or Linux had written.

A shipped gem with a C extension and no build for your platform compiles once, on your computer, for the app's Ruby. A gem in a group the app leaves out never compiles, so a game whose shipped gems are all pure Ruby or precompiled fuses without a C compiler. Any other needs one: on macOS, Xcode's command line tools (`xcode-select --install`); on Linux, a C compiler and `make` (`sudo apt install build-essential` on Debian and Ubuntu); on Windows, RubyInstaller's MSYS2 tools (`ridk install`). Without one, `lota fuse` stops after the compiler's output names the gem that failed, and says what to install. An extension compiles for the computer it compiles on, which is one more reason to build each platform's app on that platform.

Your other gems go into the app whole, with the license files their packages hold, whatever their licenses. What those licenses ask of you when you give the app to people is yours to honor, as with any Ruby program you ship: `bundle licenses` lists the license each gem declares, and a gem whose package leaves out its license text, which a license such as MIT asks you to keep with every copy, needs it added to the notices you ship.

## Notices

Every app carries a notices file, `app/NOTICES.txt`, in the folder beside the app's program (in `NAME.app/Contents/Resources` on macOS). It states Lota's license, AGPL-3.0-or-later, and names each library Lota's gem for that platform carries, compiled into Lota's extension or beside it, with its version where it is known, its licenses, and its notices of copyright. It gives FreeType's credit in the words FreeType's license asks for, says where OpenAL Soft's source archive is in the app, and ends with the text of each license it names. `lota fuse` writes it on every build from the very gem the app ships, and stops on a Lota gem that does not carry what it needs. Fledge's own `notices/NOTICES.txt`, beside it, covers Ruby and the rest of the runtime.

## A game in one file

Someone who has Lota can play your game from one file, as someone who has LÖVE plays a `.love`. Zip the game's folder, with `main.rb` at the top of the zip rather than inside a folder of its own, and rename the zip `NAME.lota`. Then:

```console
$ lota run "Sample Game.lota"
```

The game sees the archive as LÖVE's game sees a `.love`: `Lota::Filesystem` reads the archive, `Lota::Filesystem.source` names it, and the game saves under the archive's name, `Sample Game` here, unless `conf.rb` sets `t.identity`. Its Ruby, though, runs from a copy: the first time, Lota unpacks the whole archive into a folder named for the archive's contents, in `~/.cache/lota/games` on Linux (or under `XDG_CACHE_HOME`), `~/Library/Caches/Lota/games` on macOS, and `%LOCALAPPDATA%\Lota\Cache\games` on Windows, and plays it from there, as it plays a folder. So `require`, `require_relative`, `__dir__`, and `File` work as they do in your folder. The next time, it plays from that copy, unless the archive has changed or the copy is missing a file. Deleting the folder is safe; Lota unpacks the archive again.

Lota refuses an archive it cannot unpack the same way everywhere, before it writes anything, and names the entry at fault: one that would land outside the folder, such as `../main.rb`; two names that differ only by case, which Windows and macOS cannot tell apart; a name Windows forbids, with `< > : " | ? * \` or a control character in it, ending in a dot or a space, or one of Windows' device names, such as `CON` or `aux.txt`; native code, a `.so`, `.bundle`, `.dll`, or `.dylib`, which LÖVE cannot load from a `.love` either; and a symbolic link. On Windows, where long paths are not enabled, it also refuses an entry whose path in the cache would be longer than 259 characters.

## Making an app with no terminal

The fuser is an app that makes a `.lota` into an app of its own, with no Ruby, Git, compiler, or network on the computer. Open the `.lota` with the fuser: on macOS choose Lota Fuser in Finder's Open With, or run `open -a "Lota Fuser" "Sample Game.lota"`; on Linux, open it with the fuser as your desktop opens a file with an app, which hands the file to the fuser's program. Or drop the `.lota` on the fuser's window. The window shows what the fuser made: the app goes beside the `.lota`, as the files `lota fuse` writes in `dist` for that platform (see [What a player gets](#what-a-player-gets)), but on Linux with an AppImage only where `mksquashfs` is installed. Games dropped while one is made wait their turn. The fuser refuses what `lota run` refuses in a `.lota`, before it writes anything, and says why. On Windows, opening a `.lota` with the fuser, or dropping it on its window, has not been tried yet; give it to `Lota Fuser.exe` with `--build` (below), which has.

It copies itself through Fledge's `fledge build --from`, so the app it makes:

- holds the game as plain files, and only the gems the fuser ships, Lota and Fledge, so the game requires nothing else but Ruby's standard library;
- is as large as the fuser, and runs only on the system it was made on;
- is named and saves as `lota fuse` would name it and save it, and has the placeholder identifier `com.example.<identity>`, with no version and no icon of its own. For an app you sign, give your own identifier, or give an icon, use `lota fuse`.

No release carries the fuser yet. To build it, from a clone of Lota, with the gem for your platform from Lota's release:

```console
$ bundle exec rake "fuser[path/to/lota-VERSION-PLATFORM.gem]"
```

It builds as `lota fuse` builds a game, so it needs Git and the network, and writes the fuser into `dist/fuser`, as `lota fuse` writes an app into `dist`: `Lota Fuser.app` on macOS, `Lota Fuser.exe` on Windows, and `Lota Fuser` on Linux, in their archives and installers. The fuser's program also makes an app with no window, given `--build`, the `.lota`, and, if you like, the folder to write to, and prints each path it wrote. On macOS the program is `Lota Fuser.app/Contents/MacOS/Lota Fuser`:

```console
$ "Lota Fuser-x86_64-linux/Lota Fuser" --build "$HOME/Games/Sample Game.lota"
/home/you/Games/Sample Game-x86_64-linux.tar.gz
/home/you/Games/Sample Game-x86_64-linux.AppImage
```

The window prints what it shows too, each time it changes, so a fuser started from a terminal says there what it made.

## What the game prints

A fused game prints where its program's output goes: the terminal that started it, a pipe, or a file. Into a pipe or a file, Ruby holds what the game prints until its buffer fills or the game ends, as LÖVE holds a Lua game's, so a game that is killed loses what it had not yet written. To have each line written as it is printed, put this at the top of `conf.rb`, which Lota loads before anything else of your game's:

```ruby
$stdout.sync = true
```

On Windows the app opens no console, so what the game prints goes nowhere.

## Restarting, and what is missing

A fused game restarts as LÖVE's does: `Lota::Event.restart` ends it, and the app runs it again in the same process, with `Lota.restart` holding the value, as `lota run` and `bundle exec lota run` do. What the game's own files defined is gone in the new run, but what it changed outside them stays, such as a method it added to a built-in class or a gem it loaded.

What a fused game does not do yet: `lota fuse` builds no phone app; [the phone guide](phones.md) builds one with Fledge directly, or with the iOS kit from your game's CI. Ruby's YJIT is not in RubyInstaller's Ruby, so a Windows app runs without it; elsewhere the app turns YJIT on.
