#!/bin/bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Asks whether this Mac lets a script press Return on another process's
# dialog, as Plan 001's harness will to dismiss LÖVE's dialogs. It opens a
# dialog in one osascript process, then, through System Events in another,
# brings that process to the front and presses Return (key code 36), which
# needs Accessibility permission. The dialog gives up after 15 seconds, and
# each request to System Events after 10, so the probe always ends, even
# where macOS would ask a person for permission.
#
# It prints one line, "accessibility-probe: allowed" or
# "accessibility-probe: denied", with what it saw, and always exits 0: the
# answer is a fact to record, not a gate. In GitHub Actions it also writes
# the answer to the job summary and as a notice on the run.
#
# Return goes only to the probe's own dialog: the key is pressed only when
# System Events reports the dialog's process frontmost.

set -uo pipefail

session=$(launchctl managername 2>&1)
out=$(mktemp)
osascript -e 'display dialog "Lota Accessibility probe" buttons {"OK"} default button "OK" giving up after 15' \
  >"$out" 2>&1 &
dialog=$!

sent="no attempt"
for _ in $(seq 20); do
  sleep 0.5
  sent=$(osascript 2>&1 <<APPLESCRIPT
with timeout of 10 seconds
  tell application "System Events"
    if (count of (processes whose unix id is $dialog)) is 0 then return "no window yet"
    set probe to first process whose unix id is $dialog
    if (count of windows of probe) is 0 then return "no window yet"
    set frontmost of probe to true
    delay 0.5
    if not frontmost of probe then return "the dialog did not come to the front"
    key code 36
    return "sent"
  end tell
end timeout
APPLESCRIPT
  )
  [ "$sent" = "no window yet" ] || break
done

wait "$dialog"
dialog_result=$(tr '\n' ' ' <"$out")
rm -f "$out"

case "$dialog_result" in
  *"gave up:false"*) answer=allowed ;;
  *) answer=denied ;;
esac
detail="session: $session; key press: $sent; dialog: $dialog_result"
echo "accessibility-probe: $answer ($detail)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Accessibility probe: $answer"
    echo
    echo "Synthetic Return on another process's dialog was **$answer**."
    echo
    echo "- launchctl managername: \`$session\`"
    echo "- System Events: \`$sent\`"
    echo "- Dialog returned: \`$dialog_result\`"
  } >>"$GITHUB_STEP_SUMMARY"
  echo "::notice title=Accessibility probe::$answer ($detail)"
fi
exit 0
