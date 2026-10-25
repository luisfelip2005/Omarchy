#!/usr/bin/env bash
#
# Alterna o layout do teclado (br,us) e avisa qual ficou ativo.
#
# Usa `omarchy notification send` em vez de `notify-send`: o helper envia a
# notificação como "omarchy-action", que o Omarchy deixa passar mesmo com o
# modo Não Perturbe (DND) ativo — afinal o usuário acabou de pedir a troca.

set -euo pipefail

# O Hyprland reporta botões (power/sleep/video-bus) e o teclado virtual do
# fcitx5 como teclados, mas nenhum deles é o que a pessoa usa para digitar.
UNTYPED='^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus|.*button)'

hyprctl switchxkblayout all next >/dev/null
sleep 0.1

# Lê o teclado real mais avançado no ciclo, como faz o widget de layout do
# Omarchy — o flag `main` fica com o teclado virtual do fcitx5.
IDX=$(hyprctl -j devices | jq -r --arg untyped "$UNTYPED" '
  [ .keyboards[]
    | select(.name | test($untyped) | not)
  ]
  | max_by(.active_layout_index)
  | .active_layout_index // empty
')

case "$IDX" in
  0) omarchy notification send -g 󰌌 "Keyboard layout" "BR Keyboard 🇧🇷" ;;
  1) omarchy notification send -g 󰌌 "Keyboard layout" "US Keyboard 🇺🇸" ;;
esac
