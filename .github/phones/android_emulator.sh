#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Runs test/games/phone's debug APK on the emulator adb is connected to,
# for .github/workflows/phones.yml: android-emulator-runner runs each line
# of its script by itself, so the runs live here. Two launches, each into
# a folder of its own under OUT with its logcat and screenshots:
#
# 1. The game plays to its end: a tap lands on the screen, and
#    the game must say it drew, that graphics from another thread raised
#    ThreadError, that the tap arrived as a touch, and that it quits, and
#    the host must log that Ruby exited with status 0.
# 2. Back, pressed while the game runs, must reach it as the key escape
#    with scancode acback, as in LÖVE; then SDL closes the app, so the
#    game gets Lota.quit and Ruby exits with status 0.
#
#   android_emulator.sh APK IDENTIFIER OUT
set -euo pipefail
apk=$1
identifier=$2
out=$3
activity=$identifier/org.setdef.fledge.host.MainActivity
mkdir -p "$out"

adb install -r "$apk"
size=$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
read -r width height <<< "$size"
echo "screen ${width}x${height}"

# Waits up to $2 seconds for the log to hold $1.
wait_for() {
  local pattern=$1 seconds=$2
  for _ in $(seq 1 "$seconds"); do
    if adb logcat -d | grep -q -- "$pattern"; then return 0; fi
    sleep 1
  done
  return 1
}

# Fails, naming $2, unless the launch's log $1 holds each pattern after.
expect() {
  local log=$1 name=$2
  shift 2
  local missing=0
  for pattern in "$@"; do
    if ! grep -q -- "$pattern" "$log"; then
      echo "::error::$name: the log has no line matching $pattern"
      missing=1
    fi
  done
  return $missing
}

status=0

dir=$out/play
mkdir -p "$dir"
adb logcat -c
adb shell am start -W -n "$activity"
wait_for "phone check: drew frame 1" 240 || echo "::warning::the game drew no frame within 240 s"
adb exec-out screencap -p > "$dir/drawn.png"
# A game whose window is wider than tall turns the screen to landscape,
# and input tap takes the turned screen's coordinates, so the tap lands
# at a point inside the screen either way.
side=$((width < height ? width : height))
adb shell input tap $((side / 2)) $((side / 2))
sleep 2
adb exec-out screencap -p > "$dir/tapped.png"
wait_for "$identifier: .* exited with status" 120 || echo "::warning::Ruby did not exit within 120 s"
adb logcat -d -v threadtime > "$dir/logcat.txt"
expect "$dir/logcat.txt" play "phone check: loaded on Android" "phone check: another thread: ThreadError" \
  "phone check: audio playing true" "phone check: touchpressed Integer" "phone check: quits after" \
  "$identifier: .* exited with status 0" || status=1

dir=$out/back
mkdir -p "$dir"
adb shell am force-stop "$identifier"
adb logcat -c
adb shell am start -W -n "$activity"
wait_for "phone check: drew frame 1" 120 || echo "::warning::the game drew no frame within 120 s"
adb shell input keyevent KEYCODE_BACK
wait_for "$identifier: .* exited with status" 60 || echo "::warning::Ruby did not exit within 60 s of Back"
sleep 3
adb exec-out screencap -p > "$dir/after-back.png"
adb logcat -d -v threadtime > "$dir/logcat.txt"
expect "$dir/logcat.txt" back "phone check: keypressed :escape :acback" "phone check: quits after" \
  "$identifier: .* exited with status 0" || status=1

grep -h "phone check:\|$identifier: .* exited with status\|FATAL\|\[BUG\]" "$out"/*/logcat.txt || true
exit $status
