#!/bin/bash

hyprctl switchxkblayout all next
sleep 0.1

IDX=$(hyprctl -j devices | jq -r '
.keyboards[]
| select(.main == true)
| .active_layout_index
')

if [[ "$IDX" == "0" ]]; then
    notify-send "Keyboard layout" "BR Keyboard 🇧🇷"
else
    notify-send "Keyboard layout" "US Keyboard 🇺🇸"
fi
