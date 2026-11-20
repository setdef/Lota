#!/bin/bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs test/games/fuse_sandbox's app, fused by lota fuse, under the macOS
# App Sandbox, for .github/workflows/fuse.yml: it copies the app into
# WORK, signs the copy again ad hoc with the hardened runtime, the App
# Sandbox, and the two keys Fledge's signature carries
# (doc/contributors/design/packaging.md, "Signing on macOS"), and runs it
# as the Fuse workflow runs an app, with only the system's own variables
# and those named after the folders. It exits 0 only when the game
# restarted once in its process, as LÖVE's restart runs a game again in
# its own (src/love.cpp, main), and quit with 3 having run fused in a
# sandbox, and saved and read back its file in its container. On macOS
# 15 the sandbox kills a process that replaces itself with exec
# (doc/contributors/design/game.md, "Restarting").
#
#   sandbox_run.sh APP WORK [NAME=VALUE...]
set -u
source_app=$1
work=$2
shift 2
rm -rf "$work"
mkdir -p "$work/empty"
app="$work/$(basename "$source_app")"
ditto "$source_app" "$app"
name=$(basename "$app" .app)
program="$app/Contents/MacOS/$name"
plist="$work/entitlements.plist"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0">'
  echo '<dict>'
  for key in com.apple.security.app-sandbox com.apple.security.cs.allow-unsigned-executable-memory \
    com.apple.security.cs.disable-library-validation; do
    printf '\t<key>%s</key>\n\t<true/>\n' "$key"
  done
  echo '</dict>'
  echo '</plist>'
} > "$plist"
codesign --force --sign - --options runtime --entitlements "$plist" "$app" || exit 1
codesign --display --entitlements - --xml "$app" 2> /dev/null | plutil -p - || exit 1
sw_vers

touch "$work/begun"
(cd / && exec env -i PATH="$work/empty" HOME="$HOME" ${@+"$@"} "$program" > "$work/run.out" 2> "$work/run.err") &
pid=$!
for _ in $(seq 120); do kill -0 "$pid" 2> /dev/null || break; sleep 1; done
if kill -0 "$pid" 2> /dev/null; then
  echo "still running after 120 s: stopped"
  kill -9 "$pid"
fi
wait "$pid"
status=$?
echo "exit status: $status"
echo "--- stdout"; cat "$work/run.out"
echo "--- stderr (last 40 lines)"; tail -n 40 "$work/run.err"
sleep 5
find "$HOME/Library/Logs/DiagnosticReports" -newer "$work/begun" -type f -name "*$name*" 2> /dev/null |
  while read -r report; do echo "=== $report"; head -c 4000 "$report"; echo; done

out="$work/run.out"
ok=true
check() { if grep -Eq "$2" "$out"; then echo "ok: $1"; else echo "FAILED: $1"; ok=false; fi; }
if [ "$status" = 3 ]; then echo "ok: it quit with 3"; else echo "FAILED: it quit with 3"; ok=false; fi
first=$(sed -n 's/^run: \([0-9]*\) nil false$/\1/p' "$out")
if [ -n "$first" ] && [ "$(grep -c '^run: ' "$out")" = 2 ]; then
  check "it restarted once, in the same process and the same Ruby, with its value" "^run: $first $first\\.0 true\$"
else
  echo "FAILED: it ran twice, the first time fresh"
  ok=false
fi
if grep -q '^sandbox container: none$' "$out"; then
  echo "FAILED: it ran in a sandbox"
  ok=false
else
  check "it ran in a sandbox" '^sandbox container: .'
fi
check "it ran fused" '^fused: true$'
check "it saved in its container" '^save directory: .*/Library/Containers/'
check "it read back its file" '^read back: true$'
[ "$ok" = true ]
