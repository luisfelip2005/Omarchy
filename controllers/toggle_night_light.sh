#!/bin/bash
# Toggle between the automatic sun curve and the fixed preset temperature.
# Pressing it also resets the manual offset, so each press gives a known state:
# fixed = exactly preset_temperature, auto = the current solar curve.
# The preset is set in night_light.jsonc.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/night-light"
MODE_FILE="$STATE_DIR/mode"
OFFSET_FILE="$STATE_DIR/offset"
SCRIPT="$HOME/.config/hypr/controllers/night_light_dynamic.py"

mkdir -p "$STATE_DIR"

preset=$("$SCRIPT" --config 2>/dev/null | jq -r '.preset_temperature // 2500')
mode=$(cat "$MODE_FILE" 2>/dev/null || echo auto)

echo 0 > "$OFFSET_FILE"

if [[ "$mode" == "fixed" ]]; then
    echo auto > "$MODE_FILE"
    "$SCRIPT" --once >/dev/null 2>&1
    notify-send "Night light" "Automatic (follows the sun)"
else
    echo fixed > "$MODE_FILE"
    "$SCRIPT" --once >/dev/null 2>&1
    notify-send "Night light" "Fixed ${preset}K (press again for automatic)"
fi
