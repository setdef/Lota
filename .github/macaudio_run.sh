#!/bin/bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs the fused Mac Audio Check app in several ways, each with a time
# limit, and reports what each did: its exit status, its output, and, if
# it hangs, a sample of it and whether it ignores SIGTERM.
#
#   .github/macaudio_run.sh APP_BUNDLE OUT_DIR

app=$1
out=$2
mkdir -p "$out"
binary="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
limit=${LIMIT:-25}

echo "=== context"
echo "user: $(id -un) uid $(id -u)"
echo "launchctl managername: $(launchctl managername)"
launchctl print "gui/$(id -u)" 2>&1 | head -3
sw_vers
env | grep -i -E 'ALSOFT|SANDBOX|XPC' || true
ls -la ~/.alsoftrc /etc/openal/alsoft.conf ~/Library/Preferences/alsoft.conf 2>&1 || true
system_profiler SPAudioDataType 2>&1 | head -40
echo "=== Info.plist"
plutil -p "$app/Contents/Info.plist"
codesign -dvv --entitlements - "$app" 2>&1 | head -30

# watch NAME PID: waits up to $limit s for PID, samples it if it is still
# running, sends SIGTERM, and reports whether SIGTERM stopped it.
watch() {
  local name=$1 pid=$2 waited=0
  while kill -0 "$pid" 2> /dev/null && [ "$waited" -lt "$limit" ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2> /dev/null; then
    echo "$name: HUNG after $limit s"
    /usr/bin/sample "$pid" 3 -file "$out/$name.sample.txt" > /dev/null 2>&1
    grep -E 'Thread_|alcOpenDevice|CoreAudio|HALSystem|AVAUVoiceIO|AVCapture|xpc_connection_send|mach_msg' "$out/$name.sample.txt" | head -40
    kill -TERM "$pid"
    sleep 3
    if kill -0 "$pid" 2> /dev/null; then echo "$name: SIGTERM IGNORED"; kill -KILL "$pid"; else echo "$name: SIGTERM stopped it"; fi
    return 124
  fi
}

# direct NAME [VAR=VALUE...]: runs the binary itself with the variables
run_direct() {
  local name=$1
  shift
  echo "=== $name"
  env "$@" "$binary" > "$out/$name.out" 2> "$out/$name.err" &
  local pid=$!
  watch "$name" "$pid"
  wait "$pid"
  echo "$name: exit status $?"
  echo "--- stdout"; cat "$out/$name.out"; echo "--- stderr"; tail -20 "$out/$name.err"
}

# via_open NAME APP [VAR=VALUE...]: launches APP through LaunchServices
run_open() {
  local name=$1 bundle=$2
  shift 2
  echo "=== $name"
  local envs=()
  for pair in "$@"; do envs+=(--env "$pair"); done
  open -n -W --stdout "$out/$name.out" --stderr "$out/$name.err" "${envs[@]}" "$bundle" &
  local opener=$!
  sleep 3
  local pid
  pid=$(pgrep -n -f "$bundle/Contents/MacOS/")
  echo "$name: app pid ${pid:-none}"
  if [ -n "$pid" ]; then watch "$name" "$pid"; fi
  wait "$opener"
  echo "$name: open -W exit status $?"
  echo "--- stdout"; cat "$out/$name.out"; echo "--- stderr"; tail -20 "$out/$name.err"
}

run_direct direct-window
run_direct direct-nowindow MACAUDIO_WINDOW=0
run_direct direct-coreaudio MACAUDIO_WINDOW=0 ALSOFT_DRIVERS=coreaudio
run_direct direct-null MACAUDIO_WINDOW=0 ALSOFT_DRIVERS=null
echo "=== direct-clean-env (as fuse.yml, without ALSOFT_DRIVERS)"
(cd / && run_direct direct-clean-env -i PATH=/nonexistent HOME="$HOME" MACAUDIO_WINDOW=0)
run_open open-window "$app"
run_open open-nowindow "$app" MACAUDIO_WINDOW=0

mic="$out/../MicCopy/$(basename "$app")"
mkdir -p "$(dirname "$mic")"
ditto "$app" "$mic"
/usr/libexec/PlistBuddy -c 'Add :NSMicrophoneUsageDescription string "Check"' "$mic/Contents/Info.plist"
codesign --force --deep -s - "$mic"
binary="$mic/Contents/MacOS/$(basename "$binary")"
run_direct mic-direct-nowindow MACAUDIO_WINDOW=0
exit 0
