#!/bin/bash
# Less orange: add offset_step to the target temperature relative to the current
# mode (sun curve or preset). The offset compounds up to +max_offset_up.
# All values live in night_light.jsonc.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/night-light"
OFFSET_FILE="$STATE_DIR/offset"
SCRIPT="$HOME/.config/hypr/controllers/night_light_dynamic.py"

mkdir -p "$STATE_DIR"
config=$("$SCRIPT" --config 2>/dev/null)
step=$(jq -r '.offset_step // 500' <<<"$config")
limit=$(jq -r '.max_offset_up // 2000' <<<"$config")

offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
offset=$((offset + step))
(( offset > limit )) && offset=$limit
echo "$offset" > "$OFFSET_FILE"

temp=$("$SCRIPT" --once 2>/dev/null | jq -r '.temperature // empty')
notify-send "Night light" "Less orange: ${temp:-?}K (offset ${offset}K)"
