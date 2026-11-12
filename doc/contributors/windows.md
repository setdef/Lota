<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Building and Testing on Windows

Lota ships gems for Windows on x64 and ARM64, for RubyInstaller's Ruby. That Ruby is built with MinGW, and a native extension has to match it, so Lota builds LÖVE's engine and its libraries with MinGW too, where LÖVE's own Windows build uses Microsoft's compiler ([ADR 011](adr/011.md); [packaging.md](design/packaging.md)). This page says how CI builds and tests those gems, and what its tests cannot reach.

RubyInstaller publishes no Ruby 4.1 preview, so until it releases Ruby 4.1, Lota's Windows Ruby is its head build, which it rebuilds from Ruby's master every day under one URL ([ADR 013](adr/013.md)). Two days' builds can differ in ABI (`RbConfig::CONFIG["ruby_version"]`, such as `4.1.0+6`), and a gem built on one need not load in the other, so Lota pins the copy of the head build that Fledge's release keeps, the one its Windows runtime is made from. `.github/windows_ruby.env` names that copy's URL, SHA-256, and `ruby_version` for each architecture, and `.github/windows_ruby.sh` downloads it, checks both, and unpacks it. Every Windows job takes its Ruby from there (`.github/actions/windows-ruby`), and so does the pre-push script below, so CI, a push from your own computer, and a fused app run the same Ruby. Move the pin with `Lota::Fuse::FLEDGE_REF`.

The head build carries no `zlib1.dll`, which its zlib extension loads, so a Windows job sets MSYS2 up before Ruby runs and names MSYS2's MINGW `bin` folder in `RUBY_DLL_PATH`, which RubyInstaller's runtime adds before any other to where Windows looks for DLLs.

## Why the gate does not run on Windows

The gate's Bundler would compile gems that RubyInstaller's Ruby has no build of, and its lint, type, and package checks read the same sources on macOS and Linux. So Windows has a workflow of its own, `.github/workflows/windows.yml`, which builds and tests without the gate's Rake tasks; `ci.yml` calls it for both platforms, and the pre-push tier on trunk (`prepush.yml`) for x64. `.github/windows_checks.rb` holds its checks, and its steps are the recipe for a Windows build by hand.

## The Windows build job

The **Windows build** job runs once for x64 and once for ARM64:

1. It builds LÖVE's libraries from source at the versions LÖVE builds against (`tasks/windows_build.rb`), with GCC from MSYS2's UCRT64 environment on x64 and clang from its CLANGARM64 environment on ARM64, the toolchains RubyInstaller builds its Ruby with. Every library but SDL and OpenAL Soft links statically, so the extension needs no DLL but `SDL3.dll`, `OpenAL32.dll`, and Windows' own. SDL is a DLL, as LÖVE's own Windows build ships it, so the extension and the test-only extension share one SDL, as they do on macOS and Linux. SDL draws with OpenGL on both; LÖVE's own ARM64 build ships ANGLE's OpenGL ES instead, which Lota does not.
2. It checks `ext/lota/engine/sources_windows.cmake` against `vendor/love`, configures through `ext/lota/extconf.rb` with the test-only extension, and builds the engine and both extensions.
3. It checks that Lota's own code still treats warnings as errors, and that the extension's DLLs are the expected ones and load from the gem's own folder, even with a decoy of each of them on the `PATH`.
4. It restarts a game, and opens a window with Windows' own OpenGL, which passes when SDL makes a context. Windows' own OpenGL is version 1.1 and the engine refuses it, so this checks only that the window opens.
5. It builds the gem (`ruby .github/windows_checks.rb package`).
6. It runs Lota's tests on Mesa's software OpenGL, llvmpipe, as LÖVE's own Windows CI runs Lövetest. On x64 Mesa comes from mesa-dist-win's release 24.2.4, as LÖVE's does. On ARM64, which mesa-dist-win does not build for, it comes from MSYS2, with llvmpipe's linear rasterizer off (`LP_PERF=no_rast_linear`), which from Mesa 25 reads the wrong elements of a uniform array or matrix. Mesa goes beside Ruby's program, where Windows finds it before System32's.

`ruby .github/windows_checks.rb tests` runs each file of `rake test`'s suite in a Ruby of its own, keeps each one's output as the artifact `windows-tests-PLATFORM`, and lists every skip with its reason in the run's summary.

## What the tests skip on Windows

- `test/tasks`, whose tasks drive the macOS and Linux builds, and `test/native/bundle_test.rb`, which reads rpaths, do not run.
- A test that reads `/dev/fd`, deletes a file another handle holds open, or runs `lota run` under the bundle skips.
- On the ARM64 runner a window of the shell's holds the foreground, so Windows gives no test window keyboard focus. CI sets `LOTA_FOREGROUND_HELD=1` there, and Lövetest's `setGrabbed` test skips (`test/lovetest/held_foreground.rb`). LÖVE's own CI runs no Lövetest on Windows ARM64.

## The Windows delivery job

Back in `ci.yml`, the **Windows delivery** job installs the gem on a runner with only the MSYS2 setup-ruby installs, which the head build's own extensions load from, and with a `PATH` of only Ruby, Windows, PowerShell, and Git. It runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`. `fuse.yml` then fuses four games with the gem and runs the apps ([ci.md](ci.md)).

## Before a push, on a Windows computer of your own

If you have a Windows computer, Lota's Windows checks can run there before you push, instead of in CI after. Install [mise](https://mise.jdx.dev), then run `bin/setup.ps1` from PowerShell in the checkout. It installs what the checks need from Lota's own pins, and running it again changes nothing:

- RubyInstaller's x64 Ruby with winget, at the version `mise.toml` pins, since mise cannot build Ruby on Windows. It asks first, because winget may need administrator rights. While `mise.toml` pins a preview, which RubyInstaller does not publish, it installs none: the checks bring the head build `windows_ruby.env` pins, and the script needs a RubyInstaller of any version only for the MSYS2 its devkit carries.
- Python and the REUSE tool through mise, at `mise.toml`'s versions. `mise.toml` limits every other tool, Ruby included, to Linux and macOS with mise's `os` option, so mise installs no second Ruby on Windows.
- The packages `windows.yml` installs, in the MSYS2 that RubyInstaller's devkit carries: `patch`, `make`, and UCRT64's GCC, CMake, Ninja, and ccache. If it finds no MSYS2 beside Ruby, it names them.
- LÖVE's source, the `vendor/love` submodule.

It installs no bundle, since the checks run without Bundler. The script below runs itself again under `mise x`, so it finds the REUSE tool and the other tools without a `PATH` of your own, and `windows_checks.rb package` takes the same from `mise env`. From the checkout's root, in a UCRT64 shell on the computer's desktop, where windows open and the GPU draws, run:

```sh
bash .github/windows_prepush.sh
```

The script brings its own Ruby, the one `windows_ruby.env` pins, which it unpacks once into `lota` in `XDG_CACHE_HOME`, or in `~/.cache`, and keeps its gems beside. It takes `windows.yml`'s steps for x64, in their order, and installs the gems the tests need where they are missing. It leaves out the gem, which the pre-push tier leaves to the gate, and Mesa, since the computer has a GPU, and runs the tests with the pre-push tier's slow tests left out (`windows_checks.rb tests --prepush`). It builds through ccache, as CI does. The pre-push hook runs it only in a clone on Windows ([development.md](development.md)).

### The tests that need the desktop to themselves

A few tests need the visible desktop, its keyboard, mouse, and focus to themselves. They move Windows' pointer and read it back, confine it to their window, take the keyboard focus or activate a window, fill the screen, write the clipboard, or ask which window is in front. Another program on the same desktop doing any of that between their two steps fails them, and they do the same to it. The desktop input lock keeps Lota's own tests from doing it to each other, but not other projects' programs. On a desktop that is not on the screen, such as one a service gives each run of its own, Windows refuses the calls outright. `tasks/windows_desktop.rb` names those tests and says why each one needs the desktop.

So the script leaves them out (`windows_checks.rb tests --shared`), and its run can share a desktop with other work or have one of its own. To run only them, after building as before, use:

```sh
bash .github/windows_prepush.sh --desktop
```

Run it after you change Lota's input, window, or focus code, or the tests of them. Run it in a session on the visible desktop, with nobody using the keyboard or mouse and no other program's tests running. CI runs both sets, since a runner's desktop belongs to its job alone.

## What CI cannot check

GitHub's Windows runners have no GPU and no audio device. CI therefore draws only on llvmpipe, takes no input from a person, and plays sound to no real device. Outside CI, a game has been played on a Windows PC, and Lövetest passes there on an NVIDIA RTX 4090 with both Vulkan and OpenGL.
