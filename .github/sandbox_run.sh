#!/bin/bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The App Sandbox experiment (experiment/fuse-sandbox only): copies the
# app at $APP, signs the copy's bundle again ad hoc with the hardened
# runtime and the entitlement keys given after VARIANT (or keeps the
# signature lota fuse --sign - gave it, for "fledge"), runs it as the Fuse
# workflow runs an app, and says what it printed and what the system
# logged. It exits 0 only when the game quit with 3 having run fused,
# with YJIT on and its machine code entered, and saved and read back its
# file.
#
#   sandbox_run.sh VARIANT fledge
#   sandbox_run.sh VARIANT KEY...
#
# With RESTART=0 the game does not restart.

set -u
variant=$1
shift
work="$RUNNER_TEMP/variants/$variant"
rm -rf "$work"
mkdir -p "$work" "$RUNNER_TEMP/empty"
ditto "$APP" "$work/$(basename "$APP")"
app="$work/$(basename "$APP")"
name=$(basename "$app" .app)
program="$app/Contents/MacOS/$name"

if [ "$1" != fledge ]; then
  plist="$work/entitlements.plist"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    for key in "$@"; do printf '\t<key>%s</key>\n\t<true/>\n' "$key"; done
    echo '</dict>'
    echo '</plist>'
  } > "$plist"
  plutil -lint "$plist"
  codesign --force --sign - --options runtime --entitlements "$plist" "$app"
fi
echo "--- signature"
codesign --verify --deep --strict --verbose=2 "$app" 2>&1
codesign --display --verbose=2 "$app" 2>&1 | grep -E '^(Identifier|CodeDirectory|Signature|TeamIdentifier|Runtime)'
echo "--- entitlements"
codesign --display --entitlements - --xml "$app" 2> /dev/null | plutil -p - || echo "(none)"

touch "$work/begun"
begun=$(date +%s)
(cd / && exec env -i PATH="$RUNNER_TEMP/empty" HOME="$HOME" FUSE_SANDBOX_RESTART="${RESTART:-1}" "$program" > "$work/run.out" 2> "$work/run.err") &
pid=$!
for _ in $(seq 120); do kill -0 "$pid" 2> /dev/null || break; sleep 1; done
if kill -0 "$pid" 2> /dev/null; then
  echo "still running after 120 s: stopped"
  kill -9 "$pid"
fi
wait "$pid"
status=$?
echo "exit status: $status after $(( $(date +%s) - begun )) s"
echo "--- stdout"; cat "$work/run.out"
echo "--- stderr (last 40 lines)"; tail -n 40 "$work/run.err"
echo "--- the system's log of the game, secinitd, and the sandbox's reports on it"
sleep 2
log show --style compact --info --start "$(date -r "$begun" '+%Y-%m-%d %H:%M:%S')" \
  --predicate '(process == "Fuse Sandbox") || (process == "secinitd") || (process == "kernel" AND eventMessage CONTAINS "Fuse Sandbox") || (process == "launchd" AND eventMessage CONTAINS "Fuse Sandbox")' \
  2> /dev/null | grep -v -e audiomxd -e MXSession | cut -c1-600 | tail -n 60 || true
echo "--- crash reports"
sleep 5
find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports -newer "$work/begun" -type f -print 2> /dev/null | while read -r report; do
  echo "=== $report"; head -c 6000 "$report"; echo
done
echo "--- the container's save folder, seen from outside"
ls -la "$HOME/Library/Containers/"*FuseSandbox*/Data/Library/Application\ Support/FuseSandbox 2>&1 || true
ls -la "$HOME/Library/Application Support/FuseSandbox" 2>&1 || true

out="$work/run.out"
ok=true
check() { if grep -Eq "$2" "$out"; then echo "ok: $1"; else echo "FAILED: $1"; ok=false; fi; }
[ "$status" = 3 ] && echo "ok: it quit with 3" || { echo "FAILED: it quit with 3"; ok=false; }
if [ "${RESTART:-1}" = 1 ]; then check "it restarted once" '^run: [0-9]+ [0-9]+\.0$'; fi
check "it ran fused" '^fused: true$'
check "YJIT is on" '^yjit: true$'
check "YJIT compiled and entered machine code" 'compiled_iseq_count=[1-9][0-9]* compiled_iseq_entry=[1-9]'
check "it saved and read back its file" '^read back: true$'
grep -E '^(sandbox container|real home|save directory):' "$out" | sed 's/^/info: /'
[ "$ok" = true ]
