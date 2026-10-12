#!/usr/bin/env bash
#
# Ask the user (centered pop-up) whether they really want to close all
# windows. If confirmed, run the close-all action.

set -euo pipefail

choice=$(omarchy menu select "Close ALL windows?" "No" "Yes" -- --width 320 2>/dev/null || true)

if [[ "$choice" == "Yes" ]]; then
  omarchy-hyprland-window-close-all
fi
