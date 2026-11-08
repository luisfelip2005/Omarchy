#!/usr/bin/env bash
#
# Abre as janelas do setup em seus workspaces (Omarchy / Hyprland).
#
#   ws1: cmatrix + cava (terminais), btop, YouTube webapp
#   ws2: zen browser
#   ws7: whatsapp webapp
#   ws8: mission center
#   ws9: steam
#
# WS1 é montado como janelas TILED no dwindle (gaps/bordas nativas):
#   - YouTube webapp na coluna direita (altura total)
#   - coluna esquerda: cmatrix e cava em cima; btop embaixo
#
# Uso:
#   abrir_workspaces.sh            # monta tudo
#   abrir_workspaces.sh --ws1-only # só monta o workspace 1

set -euo pipefail

TERMINAL="foot"

# ---------------------------------------------------------------------------
# Helpers para conversar com o Hyprland (API Lua / hyprctl)
# ---------------------------------------------------------------------------

hlp_eval() {
  hyprctl eval "$1"
}

# Troca para o workspace N.
goto_ws() {
  hlp_eval "hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))" >/dev/null 2>&1
  sleep 0.3
}

# Lança um comando no contexto do Hyprland.
hypr_exec() {
  local cmd="$1"
  hlp_eval "hl.dispatch(hl.dsp.exec_cmd(\"$cmd\"))" >/dev/null 2>&1
}

# Foca uma janela pelo endereço.
focus_addr() {
  hlp_eval "hl.dispatch(hl.dsp.focus({ window = \"address:$1\" }))" >/dev/null 2>&1
}

# Espera até existir uma janela cuja classe casa (regex). Imprime o address.
wait_window() {
  local class_re="$1"
  local timeout="${2:-25}"
  local i
  for ((i = 0; i < timeout * 2; i++)); do
    local addr
    addr="$(
      hyprctl clients -j 2>/dev/null |
        jq -r --arg c "$class_re" '
          [ .[] | select(.class | test($c; "i")) | .address ] | first // empty'
    )"
    if [[ -n "$addr" ]]; then
      echo "$addr"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# Direciona o próximo split do dwindle.
preselect() {
  hlp_eval "hl.dispatch(hl.dsp.layout(\"preselect $1\"))" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Workspaces
# ---------------------------------------------------------------------------

open_ws1() {
  echo "→ ws1: montando cmatrix, cava, YouTube e btop (dwindle)..."

  goto_ws 1

  # 1º: YouTube webapp — ocupa a coluna direita
  hypr_exec "omarchy-launch-webapp https://youtube.com/"
  local yt
  yt="$(wait_window "chrome-youtube" 45 || true)"
  if [[ -z "$yt" ]]; then
    echo "  ! YouTube não detectado; abrindo os terminais mesmo assim"
  else
    focus_addr "$yt"
  fi

  # 2º: cmatrix — split para a esquerda (YouTube fica na direita)
  preselect left
  hypr_exec "$TERMINAL -a cmatrix cmatrix"
  local cm
  cm="$(wait_window "^cmatrix$" 15 || true)"
  [[ -n "$cm" ]] && focus_addr "$cm"

  # 3º: btop — split para baixo (rodapé da coluna esquerda)
  preselect down
  hypr_exec "$TERMINAL -a btop btop"
  wait_window "^btop$" 15 >/dev/null 2>&1 || true

  # 4º: cava — foca cmatrix e divide o topo à direita
  [[ -n "$cm" ]] && focus_addr "$cm"
  preselect right
  hypr_exec "$TERMINAL -a cava cava"
  wait_window "^cava$" 15 >/dev/null 2>&1 || true
}

open_ws2() {
  echo "→ ws2: abrindo zen browser"
  goto_ws 2
  hypr_exec "omarchy-launch-browser"
  wait_window "^zen$" 35 >/dev/null 2>&1 || true
}

open_ws7() {
  echo "→ ws7: abrindo whatsapp webapp"
  goto_ws 7
  hypr_exec "omarchy-launch-webapp https://web.whatsapp.com/"
  wait_window "chrome-web.whatsapp" 45 >/dev/null 2>&1 || true
}

open_ws8() {
  echo "→ ws8: abrindo mission center"
  goto_ws 8
  hypr_exec "flatpak run io.missioncenter.MissionCenter"
  wait_window "missioncenter" 35 >/dev/null 2>&1 || true
}

open_ws9() {
  echo "→ ws9: abrindo steam"
  goto_ws 9
  hypr_exec "steam"
  wait_window "^steam$" 45 >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------

mode="all"
for arg in "$@"; do
  case "$arg" in
    --ws1-only) mode="ws1" ;;
    --help | -h)
      sed -n '2,15p' "$0"
      exit 0
      ;;
  esac
done

if [[ "$mode" == "ws1" ]]; then
  open_ws1
  echo "Pronto. Workspace 1 montado."
  exit 0
fi

open_ws1
open_ws2
open_ws7
open_ws8
open_ws9

echo "Pronto. Ambiente montado."
