#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Runs test/games/phone's debug APK on the emulator adb is connected to,
# for .github/workflows/phones.yml: android-emulator-runner runs each line
# of its script by itself, so the runs live here. Five launches, each into
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
# 4. The display size ("wm density"), made larger, then smaller, then
#    larger than the emulator's, then reset, while the game runs, must
#    leave it running in the same process, to its own end. Density is
#    another change the manifest must declare.
# 5. Home, then the game again, then the recent apps and the game again,
#    then the screen turned off and on, must leave the game running in
#    the same process: it must hear itself hidden and shown as
#    Lota.visible, draw again, and play to its own end, with no [BUG] or
#    fatal signal. On Vulkan, a frame drawn as SDL let the window go
#    crashed the game before the host waited for it to pause
#    (doc/contributors/upstream/016.md); the log names the renderer.
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

# The display size is the density in dots per inch. Android recreates the
# activity for each change of it that configChanges leaves out, and
# SDLActivity then ends the game, and on Vulkan the present after the
# surface is gone crashes. The game keeps the scale it launched with:
# LÖVE reads the density once, and SDL passes it on only when the surface
# changes.
dir=$out/density
mkdir -p "$dir"
adb shell am force-stop "$identifier"
adb shell wm density reset
adb logcat -c
adb shell am start -W -n "$activity"
wait_for "phone check: drew frame 1" 120 || echo "::warning::the game drew no frame within 120 s"
pid=$(adb shell pidof "$identifier" || true)
base=$(adb shell wm density | sed -n 's/.*: \([0-9]*\)$/\1/p' | tail -1)
echo "density $base, process $pid"
for density in $((base * 4 / 3)) $((base * 3 / 4)) $((base * 8 / 7)); do
  adb shell wm density "$density"
  sleep 3
done
adb exec-out screencap -p > "$dir/changed.png"
adb shell wm density reset
wait_for "$identifier: .* exited with status" 120 || echo "::warning::Ruby did not exit within 120 s"
adb logcat -d -v threadtime > "$dir/logcat.txt"
expect "$dir/logcat.txt" density "phone check: quits after" "$identifier: .* exited with status 0" || status=1
refuse "$dir/logcat.txt" density "SDL *: activity finished" "SDL *: activity re-created" "\[BUG\]" || status=1
if [ -n "$pid" ] && ! grep -q -- " $pid .*phone check: quits after" "$dir/logcat.txt"; then
  echo "::error::density: the game's process was not $pid when it quit"
  status=1
fi

# Leaving the screen releases the game's window; on Vulkan a frame drawn
# as it went crashed. Each way out counts: the system pauses the game in
# onStop on Android 7 and newer, and destroys the surface after, before,
# or with no time between, by how the app leaves.
dir=$out/background
mkdir -p "$dir"
adb shell am force-stop "$identifier"
adb logcat -c
adb shell am start -W -n "$activity"
wait_for "phone check: drew frame 1" 120 || echo "::warning::the game drew no frame within 120 s"
pid=$(adb shell pidof "$identifier" || true)
adb logcat -d | grep -o "phone check: loaded on .*" | head -1
adb logcat -d | grep -q "phone check: loaded on .*renderer Vulkan" ||
  echo "::warning::background: the game is not on Vulkan here, so the check cannot fail as it did there"
sleep 2
adb shell input keyevent KEYCODE_HOME
sleep 3
adb shell am start -W -n "$activity"
sleep 2
adb shell input keyevent KEYCODE_APP_SWITCH
sleep 2
adb shell am start -W -n "$activity"
sleep 2
adb shell input keyevent KEYCODE_POWER
sleep 3
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
adb shell am start -W -n "$activity"
sleep 2
adb exec-out screencap -p > "$dir/returned.png"
wait_for "$identifier: .* exited with status" 120 || echo "::warning::Ruby did not exit within 120 s"
adb logcat -d -v threadtime > "$dir/logcat.txt"
expect "$dir/logcat.txt" background "phone check: visible false" "phone check: visible true after [1-9]" \
  "phone check: quits after" "$identifier: .* exited with status 0" || status=1
refuse "$dir/logcat.txt" background "\[BUG\]" "Fatal signal" "SDL *: activity finished" || status=1
if [ -n "$pid" ] && ! grep -q -- " $pid .*phone check: quits after" "$dir/logcat.txt"; then
  echo "::error::background: the game's process was not $pid when it quit"
  status=1
fi
last=$(grep -o "phone check: visible true after [0-9]*" "$dir/logcat.txt" | tail -1 | grep -o "[0-9]*$" || echo 0)
quit=$(grep -o "phone check: quits after [0-9]*" "$dir/logcat.txt" | tail -1 | grep -o "[0-9]*$" || echo 0)
if [ "${quit:-0}" -le "${last:-0}" ]; then
  echo "::error::background: the game drew no frame after it was last shown ($last frames then, $quit at its end)"
  status=1
fi

grep -h "phone check:\|$identifier: .* exited with status\|SDL *: activity\|FATAL\|\[BUG\]" "$out"/*/logcat.txt || true
exit $status
