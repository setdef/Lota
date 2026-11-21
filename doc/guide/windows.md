<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Making a Game on Windows

Lota needs Ruby 4.1, and until Ruby 4.1.0 is released, that Ruby is a preview. On macOS and Linux you install the preview as you would any Ruby. On Windows you cannot: [RubyInstaller](https://rubyinstaller.org/), whose Ruby Lota's Windows gems are built for, publishes no Ruby 4.1 preview. So Lota's Windows gems are built and tested on one day's head build of RubyInstaller, the copy [Fledge](https://github.com/setdef/Fledge)'s release keeps, and a game on Windows runs on that build too.

That build differs from a released RubyInstaller in three ways you meet as you set up a game: you fetch it yourself, it leans on MSYS2 for a library it does not carry, and more of your gems compile on it. This page takes them in that order, from a fresh Windows computer to a game that runs, and then to an app you can share.

Once RubyInstaller releases Ruby 4.1, a Windows game takes a released RubyInstaller as any Ruby program does, and most of this page no longer applies.

## Install MSYS2

RubyInstaller's Ruby is built with MinGW, from [MSYS2](https://www.msys2.org/)'s toolchains. MSYS2 compiles any gem with a C extension. The head build also loads `libz-1.dll` from it: its zlib extension needs that library and the build does not carry it, and without it `require "zlib"` fails, and so does every `gem install`, since a `.gem` file is compressed.

Install MSYS2 with the installer from msys2.org, in its default folder, `C:\msys64`. Install it on its own rather than through RubyInstaller's `ridk install` with option 1, which puts MSYS2 inside the Ruby's own folder, which a new pin of Ruby replaces. You install MSYS2's compiler once Ruby is in place ([below](#point-ruby-at-msys2)).

Install [Git for Windows](https://git-scm.com/download/win) as well, if you have not. `lota fuse` needs it ([Sharing a game](sharing.md#what-you-need)).

## Get Lota's Ruby

Use the very build Lota's gem was built and tested on. RubyInstaller rebuilds its head build from Ruby's master every day, under one URL, and two days' builds can differ in ABI (`RbConfig::CONFIG["ruby_version"]`, such as `4.1.0+6`), so a gem built on one day's build need not load on another's.

Lota's repository names that build in `.github/windows_ruby.env`: for each architecture, the 7z archive's URL, its SHA-256, and the `ruby_version` it reports. Read the file at the tag of the Lota release you install, as `https://github.com/setdef/Lota/blob/vVERSION/.github/windows_ruby.env`, with `VERSION` the release's number. It changes when Lota moves to a newer Fledge, so read it again when you move to a newer Lota. Take the `x64_` lines on x64 Windows and the `arm64_` lines on ARM64.

### With mise

If your game pins its tools with [mise](https://mise.jdx.dev), pin this Ruby through mise's `http` backend, which downloads the archive, checks its SHA-256, and unpacks it. The usual `ruby = "4.1.0-preview1"` does not work on Windows, where mise installs RubyInstaller's builds and RubyInstaller has none of that version, so limit it to macOS and Linux with `os`, and give Windows its own line:

```toml
# mise.toml
[tools]
ruby = { version = "4.1.0-preview1", os = ["linux", "macos"] }
"http:rubyinstaller-head" = { version = "DATE", url = "URL", checksum = "sha256:SHA256", strip_components = 1, bin_path = "bin", os = ["windows"] }
```

Put the `x64_url` value in place of `URL` and the `x64_sha256` value in place of `SHA256`. `DATE` is any name you give this build, such as the date in its URL. The archive holds one folder, which `strip_components = 1` removes, and Ruby's programs are in its `bin`. Then:

```powershell
mise install
mise exec -- ruby -e 'puts RbConfig::CONFIG[%(ruby_version)]'
```

The last command prints the `ruby_version` that `windows_ruby.env` names. The commands on the rest of this page run this Ruby and its `ridk`, `gem`, and `bundle`, so run them with mise activated in your shell, or each after `mise exec --`.

### By hand

Download the archive from its URL, and check that its SHA-256 is the one `windows_ruby.env` names:

```powershell
Get-FileHash rubyinstaller-head-x64.7z -Algorithm SHA256   # rubyinstaller-head-arm.7z on ARM64
```

Unpack it with [7-Zip](https://www.7-zip.org/) into a folder of your own, such as `C:\Ruby41`, so that `C:\Ruby41\bin\ruby.exe` is there. Then put that `bin` folder first on your `PATH`, in Windows' settings for your account's environment variables, and open a new terminal.

## Point Ruby at MSYS2

RubyInstaller's Ruby looks for MSYS2 by itself when it starts, and when a gem compiles. It looks first in `MSYS2_PATH`, then in a `msys64` folder inside or beside the Ruby's own folder, then in `C:\msys64`, then where MSYS2's installer recorded it, then on your `PATH`, and last in Scoop's apps. Once it finds MSYS2, it loads missing libraries from MSYS2's MinGW `bin` folder, and puts MSYS2's compiler and `make` on the `PATH` while a gem compiles. Before any of that, it loads libraries from each folder `RUBY_DLL_PATH` names.

So Ruby finds MSYS2 in `C:\msys64` without help. Set both variables anyway, as Lota's own Windows scripts do: they make it certain, wherever your MSYS2 is, and wherever your Ruby is. In PowerShell:

```powershell
setx MSYS2_PATH "C:\msys64"
setx RUBY_DLL_PATH "C:\msys64\ucrt64\bin"
```

On ARM64 Windows, RubyInstaller's Ruby uses MSYS2's CLANGARM64 environment, so name `C:\msys64\clangarm64\bin` in `RUBY_DLL_PATH` instead. If your MSYS2 is elsewhere, such as in the `msys64` folder of a RubyInstaller you installed before, name that folder in both.

`setx` changes the variables for terminals you open afterward, so open a new one. Then install MSYS2's compiler, with `ridk`, which comes with the Ruby:

```powershell
ridk install 2 3
```

Step 2 updates MSYS2, and step 3 installs its MinGW toolchain, `libz-1.dll` among it. Then check that Ruby loads zlib:

```powershell
ruby -rzlib -e 'puts Zlib.zlib_version'
```

It prints zlib's version. Without MSYS2, it stops with `126: The specified module could not be found` and names `zlib.so`: Windows found Ruby's zlib extension, but not the `libz-1.dll` it needs.

Either variable alone fixes `require "zlib"`. `MSYS2_PATH` also matters when a gem compiles: without it, a Ruby that cannot find your MSYS2 puts no compiler on the `PATH`, and a gem's build fails unless you compile from a shell of MSYS2's own, whose `PATH` already has one.

## Install Lota and run a game

With Ruby set up, install Lota's gem for Windows as [the README](../../README.md#installation) says: download `lota-VERSION-x64-mingw-ucrt.gem` (or `lota-VERSION-aarch64-mingw-ucrt.gem` on ARM64) and `SHA256SUMS` from the release, check the gem's SHA-256 against the file, and install it:

```powershell
gem install --local lota-VERSION-x64-mingw-ucrt.gem
lota --version
lota path\to\game
```

A game whose Ruby is all its own runs now. A game with a `Gemfile` meets two more differences. The first is its `ruby` line, if it has one. This Ruby is a head build, which calls itself 4.1.0.dev, so `bundle exec` refuses a line that names the preview exactly, such as `ruby file: ".ruby-version"` with a `.ruby-version` that says `4.1.0-preview1`: `Your Ruby version is 4.1.0.dev, but your Gemfile specified 4.1.0.preview1`. That lasts until RubyInstaller releases Ruby 4.1. `lota fuse` refuses such a line on Windows too, though it takes it on macOS and Linux, so [Sharing a game](sharing.md#your-gems) gives the line to write instead, one that admits every Ruby 4.1. The second is the gems that compile.

## Gems that compile

A gem with a C extension often publishes a precompiled build for each platform, so that installing it compiles nothing. Each precompiled build names the versions of Ruby it is built for, and some name none newer than Ruby 4.0. On Ruby 4.1, Bundler skips such a build and locks the gem's source build, which compiles when you install it. RubyGems.org lists each build of a gem, under its version, with the Ruby versions it takes.

So on Ruby 4.1, on every platform, more of a game's gems compile than on Ruby 4.0. On 2026-11-19, ffi 1.17.4, which `listen` needs through `rb-inotify`, and prism 2.1.0, which `rbs`, `steep`, and RuboCop need, were two: each precompiled build of theirs takes Ruby older than 4.1, and `bundle lock` on Lota's Windows Ruby locked `ffi (1.17.4)` and `prism (2.1.0)`, with no platform in their names. On Windows they compile with MSYS2's toolchain, so `bundle install` needs the steps above, `MSYS2_PATH` among them, even for gems your game uses only to develop or test.

Lock the platform you work on, as the README says for Lota's own gem:

```powershell
bundle lock --add-platform x64-mingw-ucrt
bundle install
```

If your game keeps its gems in `vendor/cache` and installs with `bundle install --local`, keep there the gem file the lockfile names. For a gem the lockfile locks without a platform, that is the source gem, such as `ffi-1.17.4.gem`, not `ffi-1.17.4-x64-mingw-ucrt.gem`; `bundle install --local` stops when the file the lockfile names is missing.

## Share the game

`lota fuse` builds a Windows app on Windows, into a `.zip` and a `-setup.exe` that a player runs without Ruby. The app carries Fledge's own copy of the same head build of Ruby, not yours, and `lota fuse` needs this page's MSYS2 setup to run at all, and its compiler for any gem the app ships whose C extension compiles. [Sharing a game](sharing.md) has the rest: what it needs, its options, signing a Windows app, and how it ships your gems, with the Gemfile's `ruby` line it takes and what to do when Fledge asks for Bundler's checksum ([Your gems](sharing.md#your-gems)).

The app opens no console, and Ruby's YJIT is not in RubyInstaller's Ruby, so a Windows app runs without it ([Sharing a game](sharing.md#restarting-and-what-is-missing)).
