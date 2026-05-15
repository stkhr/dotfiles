#!/bin/bash
# Focus iTerm and type `/usage` into the front Claude Code session.
# Bind this script to a global hotkey via Shortcuts.app or BetterTouchTool.
# Assumes the focused iTerm session is already running `claude` (CLI).
# Requires Accessibility permission for the invoking app (BTT / Shortcuts.app).

set -euo pipefail

osascript <<'APPLESCRIPT'
tell application "System Events"
    if not (exists process "iTerm2") then
        error "iTerm is not running" number -128
    end if
end tell

tell application "iTerm" to activate

-- Wait until iTerm is actually frontmost before sending keystrokes,
-- otherwise the first chars can be eaten by the previously focused app.
repeat 20 times
    tell application "System Events"
        if frontmost of process "iTerm2" then exit repeat
    end tell
    delay 0.05
end repeat

tell application "System Events"
    keystroke "/usage"
    key code 36
end tell
APPLESCRIPT
