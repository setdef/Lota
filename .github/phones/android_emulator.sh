#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Runs test/games/phone's debug APK on the emulator adb is connected to,
# for .github/workflows/phones.yml: android-emulator-runner runs each line
# of its script by itself, so the runs live here. Three launches, each into
# a folder of its own under OUT with its logcat and screenshots:
#
# 1. The game plays to its end: a tap lands on the screen, and
#    the game must say it drew, that graphics from another thread raised
#    ThreadError, that the tap arrived as a touch, and that it quits, and
#    the host must log that Ruby exited with status 0.
# 2. Back, pressed while the game runs, must reach it as the key escape
#    with scancode acback, as in LÖVE; then SDL closes the app, so the
#    game gets Lota.quit and Ruby exits with status 0.
# 3. Dark mode, then a font overlay, turned on while the game runs, must
#    leave it running: the game must hear the theme change as
#    Lota.themechanged and play to its own end, and SDL must never log
#    that it finished a second activity, which it does when Android
#    recreates the activity for a change the manifest does not declare
#    (uiMode and assetsPaths here).
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

# Fails, naming $2, if the launch's log $1 holds any pattern after.
refuse() {
  local log=$1 name=$2
  shift 2
  local found=0
  for pattern in "$@"; do
    if grep -q -- "$pattern" "$log"; then
      echo "::error::$name: the log has a line matching $pattern"
      found=1
    fi
  done
  return $found
}

# Right after the emulator boots, its audio server may have no output
# open yet: a run of this script launched the game then, AudioFlinger
# refused OpenSL ES's track ("could not create track, status: -22 output
# 0"), and the game played nothing, as LÖVE plays nothing without a
# device. So the launches wait, up to two minutes, for the server to list
# an output thread.
for _ in $(seq 1 120); do
  if adb shell dumpsys media.audio_flinger 2> /dev/null | grep -q "Output thread"; then break; fi
  sleep 1
done
adb shell dumpsys media.audio_flinger 2> /dev/null | grep -m 3 "Output thread" || echo "::warning::the audio server lists no output thread"

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

# Android recreates an activity for each change its manifest's
# configChanges leaves out, and SDLActivity then ends the game and exits
# the process. Dark mode changes uiMode; enabling any overlay of the
# system's, as a new wallpaper's colours do on Android 12 and later,
# changes assetsPaths.
overlay=com.android.theme.font.notoserifsource
dir=$out/changes
mkdir -p "$dir"
adb shell am force-stop "$identifier"
adb shell cmd uimode night no
adb logcat -c
adb shell am start -W -n "$activity"
wait_for "phone check: drew frame 1" 120 || echo "::warning::the game drew no frame within 120 s"
adb shell cmd uimode night yes
wait_for "phone check: themechanged :dark" 30 || echo "::warning::the game heard no theme change within 30 s"
if adb shell cmd overlay list | grep -q -- "$overlay"; then
  adb shell cmd overlay enable "$overlay"
else
  echo "::warning::the emulator has no overlay $overlay"
fi
sleep 3
adb exec-out screencap -p > "$dir/changed.png"
wait_for "$identifier: .* exited with status" 120 || echo "::warning::Ruby did not exit within 120 s"
adb shell cmd overlay disable "$overlay" || true
adb shell cmd uimode night no
adb logcat -d -v threadtime > "$dir/logcat.txt"
expect "$dir/logcat.txt" changes "phone check: themechanged :dark" "phone check: quits after" \
  "$identifier: .* exited with status 0" || status=1
refuse "$dir/logcat.txt" changes "SDL *: activity finished" "SDL *: activity re-created" "\[BUG\]" || status=1

grep -h "phone check:\|$identifier: .* exited with status\|SDL *: activity\|FATAL\|\[BUG\]" "$out"/*/logcat.txt || true
exit $status
