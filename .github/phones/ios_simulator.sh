#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Runs test/games/phone's Simulator build in a new Simulator of each
# device type named, for .github/workflows/phones.yml, each into a folder
# of its own under OUT with the app's log and screenshots. The host sends
# the game's output to the unified log under the app's identifier
# (ext/lota/phone/host/ios/Host/main.m), and simctl passes the game
# PHONE_CHECK_SECONDS as SIMCTL_CHILD_PHONE_CHECK_SECONDS. The game must
# say it drew, that graphics from another thread raised ThreadError, that
# it decoded the AIFF and M4A sounds phones.yml gives it, which only Core
# Audio decodes, at their own 48000 Hz (LÖVE's other decoders refuse them,
# and ModPlug, which can take any file, gives Decoder.h:64's 44100 Hz),
# and that it quits, and the host must log that Ruby exited with status 0.
#
#   ios_simulator.sh APP IDENTIFIER OUT DEVICE_TYPE...
set -euo pipefail
app=$1
identifier=$2
out=$3
shift 3
# shellcheck disable=SC2016 # Ruby, not the shell, reads the program.
runtime=$(xcrun simctl list runtimes -j | /usr/bin/ruby -rjson -e '
  print JSON.parse($stdin.read)["runtimes"].select { |r| r["platform"] == "iOS" && r["isAvailable"] }
    .max_by { |r| Gem::Version.new(r["version"]) }.fetch("identifier")')
echo "runtime $runtime"
status=0

for device in "$@"; do
  dir=$out/${device// /-}
  mkdir -p "$dir"
  # shellcheck disable=SC2016
  type=$(xcrun simctl list devicetypes -j | /usr/bin/ruby -rjson -e '
    print JSON.parse($stdin.read)["devicetypes"].find { |t| t["name"] == ARGV[0] }&.fetch("identifier").to_s' "$device")
  if [ -z "$type" ]; then
    echo "::warning::this Xcode has no $device; skipped"
    continue
  fi
  udid=$(xcrun simctl create "phone-check" "$type" "$runtime")
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl install "$udid" "$app"
  since=$(date "+%Y-%m-%d %H:%M:%S")
  SIMCTL_CHILD_PHONE_CHECK_SECONDS=12 xcrun simctl launch "$udid" "$identifier"
  sleep 6
  xcrun simctl io "$udid" screenshot "$dir/drawn.png" > /dev/null 2>&1 || true
  for _ in $(seq 1 120); do
    xcrun simctl spawn "$udid" log show --start "$since" --style compact --info --debug \
      --predicate "subsystem == \"$identifier\"" > "$dir/app.log" 2> /dev/null || true
    if grep -q "exited with status" "$dir/app.log"; then break; fi
    sleep 2
  done
  for pattern in "phone check: loaded on iOS" "phone check: drew frame 1" "phone check: another thread: ThreadError" \
    "phone check: audio playing true" "phone check: decoded ping.aiff at 48000 Hz, 2 channels" \
    "phone check: decoded ping.m4a at 48000 Hz, 2 channels" "phone check: quits after" "exited with status 0"; do
    if ! grep -q -- "$pattern" "$dir/app.log"; then
      echo "::error::$device: the log has no line matching $pattern"
      status=1
    fi
  done
  grep -h "phone check:\|exited with status" "$dir/app.log" || true
  find ~/Library/Logs/DiagnosticReports -name "*.ips" -newer "$dir/drawn.png" -exec cp {} "$dir/" \; 2> /dev/null || true
  xcrun simctl shutdown "$udid" || true
  xcrun simctl delete "$udid" || true
done
exit $status
