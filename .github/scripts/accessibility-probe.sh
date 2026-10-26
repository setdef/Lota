#!/bin/bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Asks whether this Mac lets a script press Return on another process's
# dialog, as Plan 001's harness will to dismiss LÖVE's dialogs. Those come
# from SDL_ShowMessageBox in the game's own process
# (vendor/love/src/modules/window/sdl/Window.cpp:1454 and 1489), a regular
# app that can come to the front. So the probe's dialog is an NSAlert in a
# regular app too: an osascript process that turns itself into one. A plain
# `display dialog` runs in osascript as it starts, a background-only process
# that System Events can never bring to the front, so a Return could never
# reach it.
#
# In another process, System Events waits for the dialog's window, brings
# its process to the front, and presses Return (key code 36), which needs
# Accessibility permission. The dialog gives up after 15 seconds, and each
# request to System Events after 10, so the probe always ends, even where
# macOS would ask a person for permission.
#
# It prints one line, "accessibility-probe:" and an answer, with what it
# saw, and always exits 0: the answer is a fact to record, not a gate.
# "allowed" means Return dismissed the dialog. "denied" means System Events
# refused to read the dialog or to press the key, or said this process may
# not script other processes' windows. "inconclusive" means the probe never
# got as far as pressing it for another reason, which the detail names. In GitHub Actions it also writes the
# answer to the job summary and as a notice on the run.
#
# Return goes only to the probe's own dialog: the key is pressed only when
# System Events reports the dialog's process frontmost.

set -uo pipefail

session=$(launchctl managername 2>&1)
out=$(mktemp)
# NSAlert's runModal returns 1000 (NSAlertFirstButtonReturn) for its only
# button, which Return presses, and -1001 (NSModalResponseAbort) when the
# timer, which runs in the modal panel's run loop mode, gives up.
osascript -l JavaScript >"$out" 2>&1 <<'JAVASCRIPT' &
ObjC.import('AppKit');
const app = $.NSApplication.sharedApplication;
app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
const alert = $.NSAlert.alloc.init;
alert.messageText = 'Lota Accessibility probe';
alert.addButtonWithTitle('OK');
app.performSelectorWithObjectAfterDelayInModes('abortModal', $(), 15, $(['NSModalPanelRunLoopMode']));
'dialog returned ' + alert.runModal;
JAVASCRIPT
dialog=$!

sent="no attempt"
for _ in $(seq 20); do
  sleep 0.5
  sent=$(osascript 2>&1 <<APPLESCRIPT
with timeout of 10 seconds
  tell application "System Events"
    try
      set probe to first process whose unix id is $dialog
    on error number -1719
      return "no window yet"
    end try
    if (count of windows of probe) is 0 then return "no window yet"
    set front_before to name of first process whose frontmost is true
    set frontmost of probe to true
    delay 0.5
    if not frontmost of probe then return "the dialog did not come to the front (frontmost: " & (name of first process whose frontmost is true) & ", before: " & front_before & ", background only: " & (background only of probe) & ")"
    key code 36
    return "sent (frontmost before: " & front_before & ")"
  end tell
end timeout
APPLESCRIPT
  )
  [ "$sent" = "no window yet" ] || break
done

wait "$dialog"
dialog_result=$(tr '\n' ' ' <"$out")
rm -f "$out"

# Without Accessibility, System Events does not refuse to list another
# process's windows; it lists none. "UI elements enabled" says whether this
# process may script them.
ui=$(osascript -e 'with timeout of 10 seconds' -e 'tell application "System Events" to get UI elements enabled' \
  -e 'end timeout' 2>&1)

# System Events says a permission is missing in words: "is not allowed
# assistive access" for reading windows, "is not allowed to send
# keystrokes" for key code. Its error numbers say less: -1719, which it
# gives for a missing permission, is also its error for a process that is
# not there yet.
case "$dialog_result:$sent" in
  *"dialog returned 1000"*) answer=allowed ;;
  *"not allowed"*) answer=denied ;;
  *) if [ "$ui" = false ]; then answer=denied; else answer=inconclusive; fi ;;
esac
detail="session: $session; UI elements enabled: $ui; System Events: $sent; dialog: $dialog_result"
echo "accessibility-probe: $answer ($detail)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Accessibility probe: $answer"
    echo
    echo "Synthetic Return on another process's dialog: **$answer**."
    echo
    echo "- launchctl managername: \`$session\`"
    echo "- UI elements enabled: \`$ui\`"
    echo "- System Events: \`$sent\`"
    echo "- Dialog: \`$dialog_result\`"
  } >>"$GITHUB_STEP_SUMMARY"
  echo "::notice title=Accessibility probe::$answer ($detail)"
fi
exit 0
