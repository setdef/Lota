#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Builds Lota's extension for each slice or ABI of PHONE as the bundles a
# release publishes beside the prebuilt engines, and shows that a phone
# build from them compiles none of Lota. It lays out test/games/phone as
# a Fledge project, as doc/guide/phones.md does, and runs fledge build
# PHONE twice:
#
# 1. with the engines in ENGINES pinned in the gem, as a release pins
#    them, and --with-lota-extension-out, so each slice's or ABI's
#    extconf.rb compiles the extension against the fetched engine and
#    packs it into OUT (ext/lota/phone/extension.rb);
# 2. with the engines and those extensions pinned, and neither Rice nor
#    a clone of Lota named, so a build that compiled the extension would
#    stop for want of --with-rice-dir.
#
# It writes OUT/SHA256SUMS for the engines and the extensions together,
# checks that the second build fetched every extension, and compares the
# two generated projects file by file, as engine_match.sh does. The second
# build's project is left in WORK/dist-prebuilt for the Simulator or the
# emulator.
#
# Run from the checkout, after bundle install, with ANDROID_NDK_ROOT for
# Android, and after making tmp/phone/lota, the folder of the gem's files,
# as the guide does. ENGINES holds the four engine bundles and their
# SHA256SUMS, as rake phone:engine and rake phone:engine:sums write them.
#
# Usage: extension_build.sh ios|android ENGINES OUT WORK

set -euo pipefail

phone=$1
engines=$(cd "$2" && pwd)
out=$3
work=$4
repo=$(pwd)
app=${APP_NAME:-PhoneCheck}
identifier=${APP_IDENTIFIER:-com.example.$app}
# The Fledge lota fuse builds with.
fledge_ref=$(ruby -Ilib -rlota/fuse -e 'print Lota::Fuse.fledge_ref(ENV)')

case "$phone" in
  ios) targets="ios-arm64 ios-arm64-simulator" ;;
  android) targets="android-arm64-v8a android-x86_64" ;;
  *) echo "usage: $0 ios|android ENGINES OUT WORK" >&2; exit 2 ;;
esac
[ -f "$engines/SHA256SUMS" ] || { echo "$engines has no SHA256SUMS" >&2; exit 2; }
[ -d tmp/phone/lota ] || { echo "make tmp/phone/lota first, as doc/guide/phones.md does" >&2; exit 2; }

rice=$(bundle info rice --path)
rm -rf "$work" "$out"
mkdir -p "$work" "$out"
work=$(cd "$work" && pwd)
out=$(cd "$out" && pwd)
project=$work/$app

# The project the guide lays out, with Lota's hosts.
mkdir -p "$project/game"
cp -R test/games/phone "$project/game/$app"
cp -R tmp/phone/lota/ext/lota/phone/host "$project/host"
if [ "$phone" = ios ]; then
  # The sounds only Core Audio decodes, which phones.yml gives the game
  # and ios_simulator.sh expects it to decode.
  sounds=$project/game/$app/decoded
  mkdir -p "$sounds"
  cp /System/Library/Sounds/Ping.aiff "$sounds/ping.aiff"
  afconvert -f m4af -d aac "$sounds/ping.aiff" "$sounds/ping.m4a"
fi
cat > "$project/main.rb" <<RUBY
# frozen_string_literal: true

# As phones.yml's: a phone restarts a game in its process.
RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)
ENV["LOTA_IN_PROCESS_RESTART"] ||= "1"
require "lota"
exit Lota::Boot.new(File.join(__dir__, "game", "$app"), ARGV, fused: true).call
RUBY
cat > "$project/Gemfile" <<RUBY
# frozen_string_literal: true

source "https://rubygems.org"

gem "lota", path: "$repo/tmp/phone/lota"
gem "fledge", git: "https://github.com/setdef/Fledge", ref: "$fledge_ref", group: :development
RUBY
cat > "$project/fledge.yml" <<YAML
name: $app
identifier: $identifier
version: 1.0.0
ios:
  host: host/ios
android:
  host: host/android
YAML
bundle exec rake "$phone:notices[$project]"

# The checksums in SUMS pinned in the gem, as a release pins them: in its
# folder and among its gemspec's files, which are all Fledge copies of a
# gem named by its path. The release the pin names is a stand-in, since
# the bundles come from a folder here (--with-lota-engine-url). It takes
# the place of any pin the checkout has, which is put back after.
gemspec=$repo/tmp/phone/lota/lota.gemspec
pin=$repo/tmp/phone/lota/ext/lota/phone/engines.txt
cp "$gemspec" "$work/lota.gemspec.unpinned"
if [ -f "$pin" ]; then
  cp "$pin" "$work/engines.txt.kept"
fi
trap 'cp "$work/lota.gemspec.unpinned" "$gemspec"; if [ -f "$work/engines.txt.kept" ]; then cp "$work/engines.txt.kept" "$pin"; else rm -f "$pin"; fi' EXIT
ruby -e 'spec = Gem::Specification.load(ARGV[0]); spec.files |= ["ext/lota/phone/engines.txt"]; File.write(ARGV[0], spec.to_ruby)' "$gemspec"
pin() {
  ruby -r ./ext/lota/phone/engine -e 'print Lota::PhoneEngine.pin_text("v0.0.0", File.read(ARGV[0]))' "$1" > "$pin"
}

# fledge build PHONE with the gem built with OPTIONS, keeping the
# generated project as dist-LABEL.
build() {
  local label=$1 options=$2 start
  (
    cd "$project"
    export BUNDLE_GEMFILE=$project/Gemfile
    bundle config set --local build.lota "$options"
    bundle lock --add-platform ruby > /dev/null
    bundle install --quiet
    rm -rf dist
    start=$(date +%s)
    bundle exec fledge build "$phone" > "$work/fledge-$label.log" 2>&1 || { tail -60 "$work/fledge-$label.log"; exit 1; }
    echo "fledge build $phone, $label: $(($(date +%s) - start)) seconds"
  )
  mv "$project/dist" "$work/dist-$label"
}

echo "== 1. The extensions, compiled against the prebuilt engines and packed"
pin "$engines/SHA256SUMS"
build compiled "--with-lota-engine-url=file://$engines/ --with-lota-engine-cache=$work/cache --with-lota-extension-out=$out --with-lota-extension-fledge=$fledge_ref --with-rice-dir=$rice"
for target in $targets; do
  cp "$engines/lota-engine-$target.tar.gz" "$out/"
done
(
  cd "$out"
  for target in $targets; do
    for kind in engine extension; do
      [ -f "lota-$kind-$target.tar.gz" ] || { echo "no lota-$kind-$target.tar.gz was made" >&2; exit 1; }
      shasum -a 256 "lota-$kind-$target.tar.gz"
    done
  done > SHA256SUMS
)
cat "$out/SHA256SUMS"

echo "== 2. A phone build from the prebuilt engines and extensions, with no Rice"
pin "$out/SHA256SUMS"
build prebuilt "--with-lota-engine-url=file://$out/ --with-lota-engine-cache=$work/cache-prebuilt"
status=0
for target in $targets; do
  if grep -q "Lota's extension for $target: $work/cache-prebuilt/" "$work/fledge-prebuilt.log"; then
    echo "$target: the extension was fetched, not compiled"
  else
    echo "$target: the build did not fetch the extension"; status=1
  fi
done
if grep -q "lota-build\|CMake could not\|Configuring done" "$work/fledge-prebuilt.log"; then
  echo "the build from the prebuilt extensions ran CMake"; status=1
fi

# An XCFramework's Info.plist as JSON, its libraries sorted by identifier
# and every dictionary's keys sorted.
xcframework_plist() {
  plutil -convert json -o - "$1" | ruby -rjson -e '
    sorted = lambda do |value|
      case value
      when Hash then value.sort.to_h { |key, inner| [key, sorted.(inner)] }
      when Array then value.map(&sorted)
      else value
      end
    end
    plist = JSON.parse($stdin.read)
    plist["AvailableLibraries"] = plist.fetch("AvailableLibraries").sort_by { |library| library.fetch("LibraryIdentifier") }
    puts JSON.generate(sorted.(plist))
  '
}

echo "== The two generated projects"
files=$(find "$work/dist-compiled" -type f | wc -l | tr -d ' ')
diff -rq "$work/dist-compiled" "$work/dist-prebuilt" > "$work/dist.diff" || true
[ -s "$work/dist.diff" ] || echo "identical: all $files files"
while IFS= read -r line; do
  case "$line" in
    # The pin itself, which differs between the two builds' gems.
    "Files $work/dist-compiled/"*"/ext/lota/phone/engines.txt and "*" differ")
      echo "expected, the pin: $line" ;;
    "Files "*" and "*" differ")
      path=${line#Files "$work"/dist-compiled/}
      path=${path%% and *}
      case "$path" in
        *.a)
          if same=$(ruby "$repo/.github/phones/same_members.rb" "$work/dist-compiled/$path" "$work/dist-prebuilt/$path"); then
            echo "$path: $same; only the dates in the archives' headers differ"
          else
            echo "$path: $same"; status=1
          fi
          ;;
        # xcodebuild -create-xcframework lists an XCFramework's libraries
        # in no fixed order, so the two are compared as data, the list
        # sorted by each library's identifier.
        *.xcframework/Info.plist)
          if [ "$(xcframework_plist "$work/dist-compiled/$path")" = "$(xcframework_plist "$work/dist-prebuilt/$path")" ]; then
            echo "$path: the same, as data with its libraries sorted by identifier"
          else
            echo "$path differs:"
            plutil -p "$work/dist-compiled/$path"
            plutil -p "$work/dist-prebuilt/$path"
            status=1
          fi
          ;;
        *) echo "$path differs"; status=1 ;;
      esac
      ;;
    *) echo "$line"; status=1 ;;
  esac
done < "$work/dist.diff"
[ "$status" -eq 0 ] && echo "✅ the build from the prebuilt extensions compiled none of Lota and matches the one that compiled it"
exit "$status"
