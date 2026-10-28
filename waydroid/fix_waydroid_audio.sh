#!/usr/bin/env bash
# =============================================================================
#  fix_waydroid_audio.sh
#
#  Corrige o áudio mudo do Waydroid sem reiniciar a sessão nem o container.
#
#  Sintoma: o vídeo roda no app Android, mas nenhum som chega ao PipeWire
#           (nenhum sink-input do Waydroid aparece em `pactl list sink-inputs`).
#  Causa:   a HAL de áudio do Android (android.hardware.audio.service) acumula
#           conexões com o servidor de som e trava; o AudioFlinger fica sem
#           caminho de saída e o app toca em silêncio.
#  Correção: reiniciar apenas o serviço da HAL. O init do Android relança o
#            serviço e o áudio volta no próximo play do app.
#
#  Uso:
#    ./fix_waydroid_audio.sh            # corrige
#    ./fix_waydroid_audio.sh --status   # só diagnostica, não mexe em nada
#    ./fix_waydroid_audio.sh --help
#
#  Não precisa de sudo: a HAL roda com o uid mapeado do usuário do desktop.
#  Depois de corrigir, pause e dê play de novo no app (o Android precisa
#  reabrir o stream de áudio).
#
#  Contexto completo: AUDIO-SEM-SOM.md, neste mesmo diretório.
# =============================================================================
export LC_ALL=C
set -Eeuo pipefail

readonly HAL_PATTERN='^/vendor/bin/hw/android\.hardware\.audio\.service'
readonly SCRIPT_NAME="${0##*/}"

notify() {
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -a Waydroid -i audio-card "$@" || true
	fi
}

hal_pids() {
	pgrep -f "$HAL_PATTERN" 2>/dev/null || true
}

pulse_clients() {
	pactl list short clients 2>/dev/null | wc -l || echo 0
}

waydroid_pulse_clients() {
	local n
	n=$(pactl list clients 2>/dev/null | grep -c 'application.name = "Waydroid"' || true)
	echo "${n:-0}"
}

waydroid_streams() {
	pactl list sink-inputs 2>/dev/null | grep -c 'application.name = "Waydroid"' || true
}

show_status() {
	local pids clients wclients streams
	pids=$(hal_pids)
	clients=$(pulse_clients)
	wclients=$(waydroid_pulse_clients)
	streams=$(waydroid_streams)

	if [ -n "$pids" ]; then
		echo "HAL de áudio do Android : ativa (pid: $(echo "$pids" | tr '\n' ' '))"
	else
		echo "HAL de áudio do Android : PARADA (o Waydroid está rodando?)"
	fi
	echo "Clientes no servidor de som : $clients (do Waydroid: $wclients)"
	echo "Streams de áudio do Waydroid : $streams"

	if [ "$streams" -eq 0 ]; then
		echo
		echo "Nenhum stream do Waydroid: ou o app está pausado, ou o áudio travou."
		echo "Se o app está tocando, rode: $SCRIPT_NAME"
	fi
}

usage() {
	cat <<EOF
$SCRIPT_NAME — corrige o áudio mudo do Waydroid

Uso:
  $SCRIPT_NAME            reinicia a HAL de áudio do Android
  $SCRIPT_NAME --status   mostra o diagnóstico (não altera nada)
  $SCRIPT_NAME --help     mostra esta ajuda

O script não usa sudo. Depois de rodar, pause e dê play de novo no app.
Mais detalhes em AUDIO-SEM-SOM.md.
EOF
}

main() {
	case "${1:-}" in
	-h | --help)
		usage
		exit 0
		;;
	--status)
		show_status
		exit 0
		;;
	"") ;;
	*)
		echo "Opção desconhecida: $1" >&2
		usage >&2
		exit 2
		;;
	esac

	old_pids=$(hal_pids)
	if [ -z "$old_pids" ]; then
		echo "A HAL de áudio do Android não está rodando. O Waydroid está aberto?" >&2
		notify -u critical "Áudio do Waydroid" "O Waydroid não está em execução."
		exit 1
	fi

	echo "Reiniciando a HAL de áudio do Android (pid: $(echo "$old_pids" | tr '\n' ' '))..."
	for pid in $old_pids; do
		kill "$pid" 2>/dev/null || true
	done

	# O init do Android relança o serviço; espera até 10 s por um pid novo.
	new_pids=""
	for _ in $(seq 1 20); do
		sleep 0.5
		new_pids=$(hal_pids)
		if [ -n "$new_pids" ] && [ "$new_pids" != "$old_pids" ]; then
			break
		fi
	done

	if [ -z "$new_pids" ] || [ "$new_pids" = "$old_pids" ]; then
		echo "A HAL de áudio não voltou. Reinicie o container:" >&2
		echo "  sudo systemctl restart waydroid-container" >&2
		notify -u critical "Áudio do Waydroid" \
			"A HAL não voltou. Reinicie o container do Waydroid."
		exit 1
	fi

	echo "HAL de áudio reiniciada (novo pid: $(echo "$new_pids" | tr '\n' ' '))."
	echo "Pause e dê play de novo no app para o Android reabrir o stream."
	echo
	show_status
	notify "Áudio do Waydroid reiniciado" "Dê play de novo no app."
}

main "$@"
