#!/bin/bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Lota's Windows checks before a push, on a Windows computer of your own
# with MSYS2's UCRT64 environment. Run it with bash from the checkout's
# root, in a session on the computer's desktop, where its tests' windows
# open. It takes windows.yml's steps for
# x64, in its order: LÖVE's dependencies from source, the engine's source
# list, the engine and both extensions through ccache, the checks of
# warnings, DLLs, loading, a restart, and an OpenGL window, and then the
# tests file by file with the pre-push tier's slow tests left out
# (windows_checks.rb tests --prepush). It leaves out the gem, which the
# tier leaves to the gate, and Mesa: a desktop has a GPU and an OpenGL
# that LÖVE's renderer takes, and a Mesa opengl32.dll beside Ruby would
# take every Ruby program's OpenGL there.
#
# Other programs may share its desktop, or the desktop may be one of its
# own that is not on the screen, so it leaves out the tests that need the
# visible desktop, its keyboard, mouse, and focus to themselves too
# (windows_checks.rb tests --shared; tasks/windows_desktop.rb). With
# --desktop it builds as before and then runs only those tests
# (windows_checks.rb tests --desktop), and none of the other checks: run
# it so after a change to Lota's input, window, or focus code, in a
# session on the visible desktop, with no one at the keyboard or mouse.
set -eu
case "${1:-}" in
  "") desktop="" ;;
  --desktop) desktop=1 ;;
  *)
    echo "usage: bash $0 [--desktop]" >&2
    exit 2
    ;;
esac
# The tools mise.toml pins, which bin/setup.ps1 installs (the REUSE tool
# among them), come through mise: run again under mise x, once.
if [ -z "${LOTA_UNDER_MISE:-}" ] && command -v mise > /dev/null 2>&1; then
  LOTA_UNDER_MISE=1 exec mise x -- bash "$0" "$@"
fi
export PATH="/ucrt64/bin:$PATH" CC=gcc CXX=g++
# The Ruby CI's Windows jobs run, which windows_ruby.env pins, rather
# than the computer's own: unpacked once into lota in XDG_CACHE_HOME, or
# in ~/.cache, with its gems kept beside it.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/lota
ruby_bin=$(bash .github/windows_ruby.sh x64 "$(cygpath -u "$cache")/windows-ruby")
RUBY_DLL_PATH=$(cygpath -w /ucrt64/bin)
MSYS2_PATH=$(cygpath -w /)
export PATH="$ruby_bin:$PATH" RUBY_DLL_PATH MSYS2_PATH
echo "ruby: $(command -v ruby); objdump: $(command -v objdump || echo none); mise: ${LOTA_UNDER_MISE:-no}"
echo "PATH starts: $(echo "$PATH" | tr ':' '\n' | head -6 | tr '\n' ' ')"
export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache
# The builds run as many jobs as tasks/jobs.rb says (LOTA_JOBS, else the
# cores and the memory available), as rake gives them.
eval "$(ruby -e 'require "./tasks/jobs"
  Jobs.environment(ENV, Jobs.count).each { |name, value| puts "export #{name}=#{value}" }')"
clean="$(cygpath -u "$(dirname "$(which ruby)")"):/c/Windows/system32:/c/Windows"
started=$(date +%s)
step() { echo "== $1 ($(( $(date +%s) - started ))s)"; }

step "the tests' gems"
gem list --installed rice --version 4.12.0 > /dev/null || gem install rice --version 4.12.0 --no-document
gem list --installed minitest --version '~> 6.0' > /dev/null || gem install minitest --version '~> 6.0' --no-document
# RuboCop at the version Gemfile.lock locks, for lib/lota/rubocop.rb's tests.
rubocop=$(ruby -e 'print File.read("Gemfile.lock")[/^    rubocop \(([^)]+)\)/, 1]')
gem list --installed rubocop --version "$rubocop" > /dev/null || gem install rubocop --version "$rubocop" --no-document
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

# The tests' PATH: MINGW_PREFIX may be a Windows path (C:/...), whose
# colon would split it.
tests_path="$clean:/c/Windows/System32/WindowsPowerShell/v1.0:/c/Program Files/Git/cmd:$(cygpath -u "$MINGW_PREFIX")/bin"

if [ -n "$desktop" ]; then
  step "the tests that need the desktop to themselves"
  PATH="$tests_path" ruby .github/windows_checks.rb tests tmp/windows-desktop-tests --desktop
  step "done"
  exit 0
fi

step "warnings as errors"
ruby .github/windows_checks.rb werror tmp/engine/build/compile_commands.json

step "the extension's DLLs"
ruby .github/windows_checks.rb closure lib/lota/native.so lib/lota/preload.so lib/lota/libraries/*.dll

# As windows.yml's check, with a decoy of each of Lota's DLLs where a
# same-named DLL could be found, unless MSYS2 has one of the name, removed
# again whatever happens.
step "loading Lota's DLLs from Lota's own directory"
mkdir -p tmp/decoy
decoys=()
trap 'rm -rf tmp/decoy "${decoys[@]}"' EXIT
for dll in lib/lota/libraries/*.dll; do
  name=$(basename "$dll")
  cp /c/Windows/System32/version.dll "tmp/decoy/$name"
  if [ ! -e "$MINGW_PREFIX/bin/$name" ]; then
    cp /c/Windows/System32/version.dll "$MINGW_PREFIX/bin/$name"
    decoys+=("$MINGW_PREFIX/bin/$name")
  fi
done
decoy=$(cygpath -w "$PWD/tmp/decoy")
PATH="$PWD/tmp/decoy:$clean" /usr/bin/timeout -k 5 120 ruby .github/windows_checks.rb load preload "$decoy"
status=0
PATH="$PWD/tmp/decoy:$clean" /usr/bin/timeout -k 5 120 ruby .github/windows_checks.rb load bare "$decoy" || status=$?
rm -rf tmp/decoy "${decoys[@]}"
trap - EXIT
[ "$status" = 3 ] || { echo "the control exited $status, not 3"; exit 1; }

step "a restart"
PATH="$clean" /usr/bin/timeout -k 5 180 ruby .github/windows_checks.rb restart

step "an OpenGL window"
PATH="$clean" /usr/bin/timeout -k 5 180 ruby .github/windows_checks.rb opengl

step "the tests"
PATH="$tests_path" ruby .github/windows_checks.rb tests tmp/windows-tests --prepush --shared

step "done"
