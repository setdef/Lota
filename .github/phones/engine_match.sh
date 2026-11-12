#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shows that a phone build from the prebuilt engines matches one from
# source. It lays out test/games/phone as a Fledge project, as
# doc/guide/phones.md does, and runs fledge build PHONE twice: once with
# the engine built from this checkout (--with-lota-source), and once with
# the engines in ENGINES, which rake phone:engine packed, fetched over
# HTTP from a server on this machine and checked against their
# SHA256SUMS, pinned in the gem's folder as a release pins them. Then it
# compares the two generated projects file by file. They carry what Lota's
# extension links: on iOS the archives, the engine's among them, which
# Xcode links into the app, and on Android libfledgeext.so, already
# linked, with libSDL3.so and libopenal.so. An archive that Apple's ar
# wrote without ZERO_AR_DATE carries its members' dates, so two archives
# that differ are compared member by member.
#
# Run from the checkout, after bundle install, rake ios:sdl3 or rake
# android:deps (with ANDROID_NDK_ROOT), and making tmp/phone/lota, the
# folder of the gem's files, as the guide does.
#
# Usage: engine_match.sh ios|android ENGINES WORK

set -euo pipefail

phone=$1
engines=$(cd "$2" && pwd)
work=$3
repo=$(pwd)
app=EngineMatch
# The Fledge lota fuse builds with.
fledge_ref=$(ruby -Ilib -rlota/fuse -e 'print Lota::Fuse.fledge_ref(ENV)')

case "$phone" in
  ios) source_options="--with-lota-sdl3=$repo/tmp/ios/sdl3" ;;
  android) source_options="--with-lota-android-deps=$repo/tmp/android/deps" ;;
  *) echo "usage: $0 ios|android ENGINES WORK" >&2; exit 2 ;;
esac
[ -f "$engines/SHA256SUMS" ] || { echo "$engines has no SHA256SUMS" >&2; exit 2; }
[ -d tmp/phone/lota ] || { echo "make tmp/phone/lota first, as doc/guide/phones.md does" >&2; exit 2; }

rice=$(bundle info rice --path)
rm -rf "$work"
mkdir -p "$work"
work=$(cd "$work" && pwd)
project=$work/$app

# The project the guide lays out, with Lota's hosts.
mkdir -p "$project/game"
cp -R test/games/phone "$project/game/$app"
cp -R tmp/phone/lota/ext/lota/phone/host "$project/host"
cat > "$project/main.rb" <<RUBY
# frozen_string_literal: true

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
identifier: com.example.$app
version: 1.0.0
ios:
  host: host/ios
android:
  host: host/android
YAML

# fledge build PHONE with the gem built with OPTIONS, keeping the
# generated project as dist-LABEL.
build() {
  local label=$1 options=$2
  (
    cd "$project"
    export BUNDLE_GEMFILE=$project/Gemfile
    bundle config set --local build.lota "$options --with-rice-dir=$rice"
    bundle lock --add-platform ruby > /dev/null
    bundle install --quiet
    rm -rf dist
    start=$(date +%s)
    bundle exec fledge build "$phone" > "$work/fledge-$label.log" 2>&1 || { tail -60 "$work/fledge-$label.log"; exit 1; }
    echo "fledge build $phone, engine $label: $(($(date +%s) - start)) seconds"
  )
  mv "$project/dist" "$work/dist-$label"
}

build source "--with-lota-source=$repo $source_options"

# The engines a release would publish, served as a release serves them,
# and their checksums pinned in the gem as a release commits them: in its
# folder and among its gemspec's files, which are all Fledge copies of a
# gem named by its path.
server=
gemspec=$repo/tmp/phone/lota/lota.gemspec
cp "$gemspec" "$work/lota.gemspec.unpinned"
trap 'cp "$work/lota.gemspec.unpinned" "$gemspec"; rm -f "$repo/tmp/phone/lota/ext/lota/phone/SHA256SUMS"; [ -z "$server" ] || kill "$server" 2> /dev/null || true' EXIT
cp "$engines/SHA256SUMS" tmp/phone/lota/ext/lota/phone/SHA256SUMS
ruby -e 'spec = Gem::Specification.load(ARGV[0]); spec.files |= ["ext/lota/phone/SHA256SUMS"]; File.write(ARGV[0], spec.to_ruby)' "$gemspec"
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$engines" > "$work/server.log" 2>&1 &
server=$!
for _ in $(seq 50); do
  python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$port/SHA256SUMS')" 2> /dev/null && break
  sleep 0.2
done
build fetched "--with-lota-engine-url=http://127.0.0.1:$port/ --with-lota-engine-cache=$work/cache"
grep "Lota's engine for" "$work/fledge-fetched.log"
echo "engines downloaded: $(grep -c "GET /lota-engine-" "$work/server.log")"

echo "== The two generated projects"
status=0
files=$(find "$work/dist-source" -type f | wc -l | tr -d ' ')
diff -rq "$work/dist-source" "$work/dist-fetched" > "$work/dist.diff" || true
if [ ! -s "$work/dist.diff" ]; then
  echo "identical: all $files files"
fi
while IFS= read -r line; do
  case "$line" in
    # The pin itself, which only the fetched build's gem carries.
    "Only in $work/dist-fetched/"*"/vendor/cache/lota/ext/lota/phone: SHA256SUMS" | \
      "Files $work/dist-source/"*"/vendor/cache/lota/lota.gemspec and "*" differ")
      echo "expected, the pin: $line" ;;
    "Files "*" and "*" differ")
      path=${line#Files "$work"/dist-source/}
      path=${path%% and *}
      case "$path" in
        *.a)
          if same=$(ruby "$repo/.github/phones/same_members.rb" "$work/dist-source/$path" "$work/dist-fetched/$path"); then
            echo "$path: $same; only the dates in the archives' headers differ"
          else
            echo "$path: $same"; status=1
          fi
          ;;
        *) echo "$path differs"; status=1 ;;
      esac
      ;;
    *) echo "$line"; status=1 ;;
  esac
done < "$work/dist.diff"
echo "== Each engine archive the projects carry"
find "$work/dist-fetched" -name "liblota_engine.a" -exec shasum -a 256 {} + | sed "s|$work/||"
find "$work/dist-fetched" -name "*.so" -exec shasum -a 256 {} + | sed "s|$work/||"
[ "$status" -eq 0 ] && echo "✅ the build from the fetched engines matches the build from source"
exit "$status"
