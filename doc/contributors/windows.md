<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Building and Testing on Windows

Lota ships gems for Windows on x64 and ARM64, for RubyInstaller's Ruby. That Ruby is built with MinGW, and a native extension has to match it, so Lota builds LÖVE's engine and its libraries with MinGW too, where LÖVE's own Windows build uses Microsoft's compiler ([ADR 011](adr/011.md); [packaging.md](design/packaging.md)). This page says how CI builds and tests those gems, and what its tests cannot reach.

## Why the gate does not run on Windows

The gate's Bundler would compile gems that RubyInstaller's Ruby has no build of, and its lint, type, and package checks read the same sources on macOS and Linux. So Windows has a workflow of its own, `.github/workflows/windows.yml`, which builds and tests without the gate's Rake tasks; `ci.yml` calls it for both platforms, and the pre-push tier on trunk (`prepush.yml`) for x64. `.github/windows_checks.rb` holds its checks, and its steps are the recipe for a Windows build by hand.

## The Windows build job

The **Windows build** job runs once for x64 and once for ARM64:

1. It builds LÖVE's libraries from source at the versions LÖVE builds against (`tasks/windows_build.rb`), with GCC from MSYS2's UCRT64 environment on x64 and clang from its CLANGARM64 environment on ARM64, the toolchains RubyInstaller builds its Ruby with. Every library but OpenAL Soft links statically, so the extension needs no DLL but `OpenAL32.dll` and Windows' own. SDL draws with OpenGL on both; LÖVE's own ARM64 build ships ANGLE's OpenGL ES instead, which Lota does not.
2. It checks `ext/lota/engine/sources_windows.cmake` against `vendor/love`, configures through `ext/lota/extconf.rb` with the test-only extension, and builds the engine and both extensions.
3. It checks that Lota's own code still treats warnings as errors, and that the extension's DLLs are the expected ones and load from the gem's own folder, even with a decoy `OpenAL32.dll` on the `PATH`.
4. It restarts a game, and opens a window with Windows' own OpenGL, which passes when SDL makes a context. Windows' own OpenGL is version 1.1 and the engine refuses it, so this checks only that the window opens.
5. It builds the gem (`ruby .github/windows_checks.rb package`).
6. It runs Lota's tests on Mesa's software OpenGL, llvmpipe, as LÖVE's own Windows CI runs Lövetest. On x64 Mesa comes from mesa-dist-win's release 24.2.4, as LÖVE's does. On ARM64, which mesa-dist-win does not build for, it comes from MSYS2, with llvmpipe's linear rasterizer off (`LP_PERF=no_rast_linear`), which from Mesa 25 reads the wrong elements of a uniform array or matrix. Mesa goes beside Ruby's program, where Windows finds it before System32's.

`ruby .github/windows_checks.rb tests` runs each file of `rake test`'s suite in a Ruby of its own, keeps each one's output as the artifact `windows-tests-PLATFORM`, and lists every skip with its reason in the run's summary.

## What the tests skip on Windows

- `test/tasks`, whose tasks drive the macOS and Linux builds, and `test/native/bundle_test.rb`, which reads rpaths, do not run.
- SDL is linked into each extension on Windows, so the test extension cannot reach the SDL that Lota's windows and input run on. The tests that hold keys, push events, or plug in virtual joysticks through it skip (`test/native/windows_support.rb`).
- A test that reads `/dev/fd`, deletes a file another handle holds open, or runs `lota run` under the bundle skips.
- On the ARM64 runner a window of the shell's holds the foreground, so Windows gives no test window keyboard focus. CI sets `LOTA_FOREGROUND_HELD=1` there, and Lövetest's `setGrabbed` test skips (`test/lovetest/held_foreground.rb`). LÖVE's own CI runs no Lövetest on Windows ARM64.

## The Windows delivery job

Back in `ci.yml`, the **Windows delivery** job installs the gem on a runner without MSYS2, with a `PATH` of only Ruby, Windows, PowerShell, and Git. It runs a game that opens no window and plays a sound through the gem's `OpenAL32.dll`. `fuse.yml` then fuses three games with the gem and runs the apps ([ci.md](ci.md)).

## Before a push, on a Windows computer of your own

If you have a Windows computer you can reach over ssh, with MSYS2's UCRT64 environment, RubyInstaller's x64 Ruby, and a desktop job runner (`agent-job`, which runs each job in the signed-in desktop session, where windows open and the GPU draws), Lota's Windows checks can run there before you push, instead of in CI after:

```sh
LOTA_WINDOWS_HOST=you@your-pc LOTA_WINDOWS_KEY=~/.ssh/your_pc_key bundle exec rake gate:windows
```

`gate:windows` sends `HEAD`, or a commit of your working tree, as a git bundle written as base64, since PowerShell's pipes mangle binary data, into a folder under the account's home (`LOTA_WINDOWS_RUNNER`, `lota-prepush` unless set). It then submits one job, alone on the desktop, that clones Lota there if it has no clone yet, checks the commit out, and runs `.github/windows_prepush.sh` from it. That script takes `windows.yml`'s steps for x64, without the gem and without Mesa, since the computer has a GPU, and runs the tests with the pre-push tier's slow tests left out (`windows_checks.rb tests --prepush`). With `LOTA_WINDOWS_HOST` set, the pre-push hook runs the same checks on what you push, after `rake prepush` and `rake red_before_green` pass ([development.md](development.md)). `tasks/remote_windows.rb` holds the details.

## What CI cannot check

GitHub's Windows runners have no GPU and no audio device. CI therefore draws only on llvmpipe, takes no input from a person, and plays sound to no real device. Outside CI, a game has been played on a Windows PC, and Lövetest passes there on an NVIDIA RTX 4090 with both Vulkan and OpenGL.
