#!/bin/bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Lota's Windows checks before a push, on a Windows computer of your own
# with MSYS2's UCRT64 environment and RubyInstaller's x64 Ruby, from the
# checkout's root (tasks/remote_windows.rb runs it there, through the
# computer's desktop job runner). It takes windows.yml's steps for x64,
# in its order: LÖVE's dependencies from source, the engine's source
# list, the engine and both extensions through ccache, the checks of
# warnings, DLLs, loading, a restart, and an OpenGL window, and then the
# tests file by file with the pre-push tier's slow tests left out
# (windows_checks.rb tests --prepush). It leaves out the gem, which the
# tier leaves to the gate, and Mesa: a desktop has a GPU and an OpenGL
# that LÖVE's renderer takes, and a Mesa opengl32.dll beside Ruby would
# take every Ruby program's OpenGL there.
set -eu
export PATH="/ucrt64/bin:$PATH" CC=gcc CXX=g++
export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache
clean="$(cygpath -u "$(dirname "$(which ruby)")"):/c/Windows/system32:/c/Windows"
started=$(date +%s)
step() { echo "== $1 ($(( $(date +%s) - started ))s)"; }

step "the tests' gems"
gem list --installed rice --version 4.12.0 > /dev/null || gem install rice --version 4.12.0 --no-document
gem list --installed minitest --version '~> 6.0' > /dev/null || gem install minitest --version '~> 6.0' --no-document
if ! gem list --installed desktop_input_lock --version 0.2.0 > /dev/null; then
  lock=$(mktemp -d)
  git clone --quiet --depth 1 --branch v0.2.0 https://github.com/setdef/DesktopInputLock.git "$lock"
  (cd "$lock" && gem build --quiet ./*.gemspec && gem install --local --no-document ./*.gem)
  rm -rf "$lock"
fi

step "LÖVE's dependencies"
CMAKE_C_COMPILER_LAUNCHER="" CMAKE_CXX_COMPILER_LAUNCHER="" ruby -e 'require "./tasks/windows_build"
  build = WindowsBuild.new(sources: WindowsBuild::SOURCES, root: "tmp/dependencies")
  build.fetch
  build.dependencies'

step "the engine's source list"
# shellcheck disable=SC2016 # Ruby's backticks, not the shell's
ruby -e 'require "./tasks/engine_sources"
  commit = `git -C vendor/love rev-parse HEAD`.strip
  s = EngineSources.new(source: "vendor/love", build: "tmp/engine/sources/windows",
    cmake_args: EngineSources.cmake_args("windows"), label: EngineSources.label(commit, "windows"))
  problems = s.problems("ext/lota/engine/sources_windows.cmake")
  abort problems.join("\n") unless problems.empty?'

step "the engine and the extensions"
mkdir -p tmp/ext
(cd tmp/ext && ruby ../../ext/lota/extconf.rb "--with-cmake-build-dir=$(cygpath -m "$PWD/../engine/build")" --enable-native-test > /dev/null)
make --silent -C tmp/ext install sitearchdir="$PWD/lib"

step "warnings as errors"
ruby .github/windows_checks.rb werror tmp/engine/build/compile_commands.json

step "the extension's DLLs"
ruby .github/windows_checks.rb closure lib/lota/native.so lib/lota/preload.so lib/lota/libraries/OpenAL32.dll

# As windows.yml's check, with a decoy OpenAL32.dll where a same-named
# DLL could be found, removed again whatever happens.
step "loading Lota's DLLs from Lota's own directory"
mkdir -p tmp/decoy
cp /c/Windows/System32/version.dll tmp/decoy/OpenAL32.dll
cp /c/Windows/System32/version.dll "$MINGW_PREFIX/bin/OpenAL32.dll"
trap 'rm -rf tmp/decoy "$MINGW_PREFIX/bin/OpenAL32.dll"' EXIT
decoy=$(cygpath -w "$PWD/tmp/decoy")
PATH="$PWD/tmp/decoy:$clean" /usr/bin/timeout -k 5 120 ruby .github/windows_checks.rb load preload "$decoy"
status=0
PATH="$PWD/tmp/decoy:$clean" /usr/bin/timeout -k 5 120 ruby .github/windows_checks.rb load bare "$decoy" || status=$?
rm -rf tmp/decoy "$MINGW_PREFIX/bin/OpenAL32.dll"
trap - EXIT
[ "$status" = 3 ] || { echo "the control exited $status, not 3"; exit 1; }

step "a restart"
PATH="$clean" /usr/bin/timeout -k 5 180 ruby .github/windows_checks.rb restart

step "an OpenGL window"
PATH="$clean" /usr/bin/timeout -k 5 180 ruby .github/windows_checks.rb opengl

step "the tests"
PATH="$clean:/c/Windows/System32/WindowsPowerShell/v1.0:/c/Program Files/Git/cmd:$MINGW_PREFIX/bin" \
  ruby .github/windows_checks.rb tests tmp/windows-tests --prepush

step "done"
