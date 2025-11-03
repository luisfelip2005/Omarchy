#!/bin/bash

STATE_FILE="/tmp/hyprsunset_state"

if [[ -f "$STATE_FILE" && $(cat "$STATE_FILE") == "on" ]]; then
    hyprctl hyprsunset identity
    echo "off" > "$STATE_FILE"
    notify-send "Hyprsunset" "Night light disabled"
else
    hyprctl hyprsunset temperature 2000
    echo "on" > "$STATE_FILE"
    notify-send "Hyprsunset" "Night light enabled"
fi
