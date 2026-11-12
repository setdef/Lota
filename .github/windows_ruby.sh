#!/bin/bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Usage: .github/windows_ruby.sh ARCH CACHE
#
# Makes the Ruby .github/windows_ruby.env pins for ARCH (x64 or arm64)
# ready under the folder CACHE, and prints its bin folder. It downloads
# the 7z once, refuses it unless its SHA-256 is the pinned one, unpacks
# it into CACHE/<sha256>, which later runs reuse, and refuses a Ruby
# whose RbConfig::CONFIG["ruby_version"] is not the pinned one. The
# Windows jobs (.github/actions/windows-ruby) and the Windows pre-push
# checks (.github/windows_prepush.sh) both take their Ruby from here.
#
# The caller puts the bin folder first on PATH, and names the MSYS2
# MINGW bin folder in RUBY_DLL_PATH: RubyInstaller's head build carries
# no zlib1.dll, which its zlib extension needs, and its runtime searches
# that variable's folders first.
set -euo pipefail
arch=${1:?usage: windows_ruby.sh ARCH CACHE}
cache=${2:?usage: windows_ruby.sh ARCH CACHE}
here=$(cd "$(dirname "$0")" && pwd)

value() {
  local line
  line=$(grep -E "^${arch}_$1=" "$here/windows_ruby.env" | tail -1) || true
  [ -n "$line" ] || { echo "windows_ruby.sh: windows_ruby.env names no ${arch}_$1" >&2; exit 1; }
  echo "${line#*=}"
}
url=$(value url)
sha256=$(value sha256)
ruby_version=$(value ruby_version)
case "$url$sha256" in
  *PENDING*)
    echo "windows_ruby.sh: windows_ruby.env pins no $arch Ruby yet ($url); it waits for the head build Fledge's release keeps" >&2
    exit 1 ;;
esac

# Each run unpacks into a folder of its own and renames it into place,
# so two runs at once never see half a Ruby.
home="$cache/$sha256"
if [ ! -d "$home" ]; then
  mkdir -p "$cache"
  work=$(mktemp -d "$cache/.unpack.XXXXXX")
  curl --fail --location --silent --show-error --retry 3 -o "$work/ruby.7z" "$url"
  actual=$(sha256sum "$work/ruby.7z" | cut -d' ' -f1)
  if [ "$actual" != "$sha256" ]; then
    echo "windows_ruby.sh: $url has SHA-256 $actual, not the pinned $sha256" >&2
    rm -rf "$work"
    exit 1
  fi
  # RubyInstaller packs its ARM64 build with 7-Zip's ARM64 filter, which
  # MSYS2's p7zip, the 7z a shell of setup-ruby's or setup-msys2's MSYS2
  # finds first, cannot unpack ("Unsupported Method"); 7-Zip's own, which
  # a runner installs, can.
  if [ -x "/c/Program Files/7-Zip/7z.exe" ]; then
    "/c/Program Files/7-Zip/7z.exe" x -y -o"$(cygpath -w "$work/unpacked")" "$(cygpath -w "$work/ruby.7z")" > /dev/null
  else
    7z x -y -o"$work/unpacked" "$work/ruby.7z" > /dev/null
  fi
  rm "$work/ruby.7z"
  mv -T "$work" "$home" 2> /dev/null || rm -rf "$work"
fi

folders=("$home"/unpacked/*/)
[ ${#folders[@]} -eq 1 ] || { echo "windows_ruby.sh: $url unpacks to ${#folders[@]} folders, not one" >&2; exit 1; }
bin="${folders[0]%/}/bin"
actual=$("$bin/ruby.exe" -e 'print RbConfig::CONFIG["ruby_version"]')
if [ "$actual" != "$ruby_version" ]; then
  echo "windows_ruby.sh: $url is Ruby $actual, not the pinned $ruby_version" >&2
  exit 1
fi
echo "$bin"
