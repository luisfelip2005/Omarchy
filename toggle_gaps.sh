#!/bin/bash

# Get the first number of gaps_in
gaps_in=$(hyprctl getoption general:gaps_in | head -1 | awk '{print $3}')

# Toggle logic
if [ "$gaps_in" -gt 0 ]; then
    # If gaps are active, disable them
    hyprctl keyword general:gaps_in 0
    hyprctl keyword general:gaps_out 0
    hyprctl keyword decoration:rounding 0
    hyprctl keyword general:border_size 0

    notify-send "Hyprland" "Gaps disabled"
else
    # If gaps are zero, restore defaults
    hyprctl keyword general:gaps_in 5
    hyprctl keyword general:gaps_out 10
    hyprctl keyword decoration:rounding 8
    hyprctl keyword general:border_size 2


    notify-send "Hyprland" "Gaps enabled"
fi
