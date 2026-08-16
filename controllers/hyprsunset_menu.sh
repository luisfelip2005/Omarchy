#!/bin/bash

ensure_running() {
  if ! pgrep -x hyprsunset >/dev/null; then
    setsid uwsm-app -- hyprsunset >/dev/null 2>&1 &
    sleep 1
  fi
}

enable_sunset() {
  ensure_running
  read -rp "Temperature in Kelvin (e.g. 2000, 4000): " temp
  if [[ ! "$temp" =~ ^[0-9]+$ ]] || (( temp < 1000 || temp > 8000 )); then
    echo "Invalid temperature. Use a value between 1000 and 8000 K."
    return 1
  fi
  hyprctl hyprsunset temperature "$temp"
  echo "on" > /tmp/hyprsunset_state
  notify-send "Hyprsunset" "Night light enabled at ${temp}K"
}

disable_sunset() {
  ensure_running
  hyprctl hyprsunset identity
  echo "off" > /tmp/hyprsunset_state
  notify-send "Hyprsunset" "Night light disabled"
}

echo "Hyprsunset"
echo "1) Enable sunset"
echo "2) Disable sunset"
read -rp "Choose: " choice

case "$choice" in
  1) enable_sunset ;;
  2) disable_sunset ;;
  *) echo "Invalid option." ;;
esac