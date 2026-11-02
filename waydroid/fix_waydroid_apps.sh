#!/usr/bin/env bash
# =============================================================================
#  fix_waydroid_apps.sh
#
#  Corrige o motivo pelo qual Nio Player (com.nio.smart.player) e STV
#  (com.bx.livf) ficam presos na splash / não abrem no Waydroid.
#
#  Causa diagnosticada nesta máquina:
#    O UFW está ativo com DEFAULT_FORWARD_POLICY=DROP e as regras de rota do
#    Waydroid apontam para interfaces WAN antigas (enp0s29u1u5/enp0s29u1u2).
#    A WAN atual é outra (enp6s0). Resultado:
#      - ICMP (ping) passa, porque o ufw-before-forward aceita echo-request;
#      - DNS passa, porque o dnsmasq roda no host (entrada, não forward);
#      - TCP para fora é DROPado no FORWARD.
#    Sem TCP, os dois apps não carregam a API/playlist e ficam na splash.
#
#  O que o script faz:
#    1. Confere/sobe container e sessão do Waydroid;
#    2. Corrige UFW/iptables/NAT com regras que NÃO dependem do nome da WAN;
#    3. Persiste a correção (NetworkManager dispatcher + timer systemd);
#    4. Configura ADB TCP (baixa platform-tools se faltar, grava a chave);
#    5. Valida TCP de dentro do Android;
#    6. Reabre Nio (auto-login pela SplashActivity) e STV (IndexActivity);
#    7. Valida foco/processo e mostra o resultado.
#
#  Uso:
#    sudo ./fix_waydroid_apps.sh              # corrige e abre os dois apps
#    sudo ./fix_waydroid_apps.sh --check      # só diagnostica (não altera)
#    sudo ./fix_waydroid_apps.sh --no-persist # corrige sem criar timer/dispatcher
#    ./fix_waydroid_apps.sh --help
#
#  Não apaga dados de nenhum app. Não reinstala APK. Não reinicia o container
#  sem necessidade.
# =============================================================================
set -Eeuo pipefail
export LC_ALL=C

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ORIG_ARGS=("$@")
MODE="fix"
PERSIST=1

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_BLUE=$'\033[1;34m'
	C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
	C_CYAN=$'\033[1;36m'
else
	C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

log()  { printf '%s[fix-apps]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
die()  { err "$*"; exit 1; }

trap 'err "comando falhou (rc=$?): $BASH_COMMAND (linha $LINENO)"' ERR

usage() {
	sed -n '2,40p' "$SELF" | sed 's/^# \{0,1\}//'
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--check|--diagnose) MODE="check" ;;
		--no-persist)       PERSIST=0 ;;
		-h|--help)          usage ;;
		*) die "Opção desconhecida: $1 (use --help)" ;;
	esac
	shift
done

AM_ROOT=0
[[ ${EUID} -eq 0 ]] && AM_ROOT=1

if [[ "$MODE" == "fix" && $AM_ROOT -eq 0 ]]; then
	command -v sudo >/dev/null 2>&1 || die "sudo não encontrado; rode como root."
	log "Elevando privilégios com sudo..."
	exec sudo -E bash "$SELF" "${ORIG_ARGS[@]}"
fi

# ---------------------------------------------------------------------------
# Usuário do desktop e execução como ele
# ---------------------------------------------------------------------------
detect_target_user() {
	if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
		TARGET_USER="$SUDO_USER"
	elif [[ $AM_ROOT -eq 0 ]]; then
		TARGET_USER="$(id -un)"
	else
		TARGET_USER="$(loginctl list-sessions --no-legend 2>/dev/null \
			| awk '$3 != "" {print $3; exit}')"
		if [[ -z "${TARGET_USER:-}" ]]; then
			TARGET_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')"
		fi
	fi
	[[ -n "${TARGET_USER:-}" ]] || die "Não foi possível detectar o usuário do desktop."
	TARGET_UID="$(id -u "$TARGET_USER")"
	TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
	TARGET_RUNTIME="/run/user/${TARGET_UID}"
}

run_as_user() {
	local wl=""
	wl="$(find "$TARGET_RUNTIME" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' 2>/dev/null | head -n1 || true)"
	local envs=(
		HOME="$TARGET_HOME"
		USER="$TARGET_USER"
		LOGNAME="$TARGET_USER"
		XDG_RUNTIME_DIR="$TARGET_RUNTIME"
		DBUS_SESSION_BUS_ADDRESS="unix:path=${TARGET_RUNTIME}/bus"
		DISPLAY="${DISPLAY:-:0}"
		PATH="/usr/local/bin:/usr/bin:/bin"
	)
	[[ -n "$wl" ]] && envs+=(WAYLAND_DISPLAY="$wl")
	if [[ $AM_ROOT -eq 1 && "$TARGET_USER" != "root" ]]; then
		runuser -u "$TARGET_USER" -- env "${envs[@]}" "$@"
	else
		env "${envs[@]}" "$@"
	fi
}

detect_target_user

# ---------------------------------------------------------------------------
# Waydroid: container, sessão, IP
# ---------------------------------------------------------------------------
waydroid_status() { run_as_user waydroid status 2>/dev/null || true; }

waydroid_ip() {
	waydroid_status | awk -F'\t' '/IP address/ {print $2}' | tr -d ' ' | head -n1
}

ensure_container() {
	step "Container do Waydroid"
	if systemctl is-active --quiet waydroid-container 2>/dev/null; then
		ok "waydroid-container ativo"
	else
		log "Iniciando waydroid-container..."
		systemctl start waydroid-container 2>/dev/null || warn "Falha ao iniciar o container."
	fi

	local i
	for i in $(seq 1 30); do
		if waydroid_status | grep -Eq 'Container:[[:space:]]+RUNNING'; then
			ok "container RUNNING"
			return 0
		fi
		sleep 1
	done
	warn "Container não chegou a RUNNING."
	return 1
}

ensure_session() {
	step "Sessão do Waydroid"
	if waydroid_status | grep -Eq 'Session:[[:space:]]+RUNNING'; then
		ok "sessão RUNNING"
		return 0
	fi

	log "Iniciando sessão..."
	run_as_user systemctl --user start waydroid-session.service >/dev/null 2>&1 || true
	if ! waydroid_status | grep -Eq 'Session:[[:space:]]+RUNNING'; then
		run_as_user bash -c 'nohup waydroid session start >/tmp/waydroid-session.log 2>&1 &' \
			>/dev/null 2>&1 || true
	fi

	local i
	for i in $(seq 1 60); do
		if waydroid_status | grep -Eq 'Session:[[:space:]]+RUNNING'; then
			ok "sessão RUNNING"
			return 0
		fi
		sleep 1
	done
	warn "Sessão não iniciou. Veja: journalctl --user -u waydroid-session"
	return 1
}

# ---------------------------------------------------------------------------
# ADB TCP
# ---------------------------------------------------------------------------
ADB=""

find_adb() {
	local c
	for c in \
		"$(command -v adb 2>/dev/null || true)" \
		/tmp/opencode/platform-tools/adb \
		"${TARGET_HOME}/.local/share/waydroid-tools/platform-tools/adb"; do
		if [[ -n "$c" && -x "$c" ]]; then
			ADB="$c"
			return 0
		fi
	done
	return 1
}

ensure_adb() {
	step "ADB TCP"
	if find_adb; then
		ok "adb: $ADB"
		return 0
	fi

	if [[ "$MODE" == "check" ]]; then
		warn "adb não encontrado; verificações Android serão puladas."
		return 1
	fi

	local dest="${TARGET_HOME}/.local/share/waydroid-tools"
	local zip="${dest}/platform-tools.zip"
	log "Baixando Android platform-tools para $dest ..."
	run_as_user mkdir -p "$dest"
	run_as_user /usr/bin/curl -fsSL --max-time 180 -o "$zip" \
		https://dl.google.com/android/repository/platform-tools-latest-linux.zip

	if command -v unzip >/dev/null 2>&1; then
		run_as_user /usr/bin/unzip -oq "$zip" -d "$dest"
	else
		run_as_user /usr/bin/python3 -m zipfile -e "$zip" "$dest"
	fi
	ADB="${dest}/platform-tools/adb"
	chmod 755 "$ADB" 2>/dev/null || true
	[[ -x "$ADB" ]] || die "Falha ao instalar o adb."
	ok "adb instalado: $ADB"
}

adb_cmd() { run_as_user "$ADB" "$@"; }

ensure_adb_keys() {
	local keydir="${TARGET_HOME}/.local/share/waydroid/data/misc/adb"
	run_as_user mkdir -p "${TARGET_HOME}/.android" "$keydir" >/dev/null 2>&1 || true
	if [[ ! -f "${TARGET_HOME}/.android/adbkey" ]]; then
		run_as_user "$ADB" keygen "${TARGET_HOME}/.android/adbkey" >/dev/null 2>&1 || true
	fi
	[[ -f "${TARGET_HOME}/.android/adbkey.pub" ]] || return 1
	run_as_user sh -c "cat '${TARGET_HOME}/.android/adbkey.pub' > '${keydir}/adb_keys'" \
		>/dev/null 2>&1 || return 1
	chmod 640 "${keydir}/adb_keys" 2>/dev/null || true
}

connect_adb() {
	local ip="$1" state out
	adb_cmd kill-server >/dev/null 2>&1 || true
	ensure_adb_keys || warn "Não consegui gravar adb_keys; tentando mesmo assim."

	local attempt
	for attempt in 1 2 3; do
		out="$(adb_cmd connect "${ip}:5555" 2>&1 || true)"
		sleep 2
		state="$(adb_cmd devices 2>/dev/null | awk -v d="${ip}:5555" '$1==d {print $2}' | head -n1 || true)"
		if [[ "$state" == "device" ]]; then
			ok "ADB conectado: ${ip}:5555"
			return 0
		fi
		if [[ "$state" == "unauthorized" ]]; then
			warn "ADB unauthorized; regravando chave (tentativa ${attempt}/3)..."
			ensure_adb_keys || true
			adb_cmd kill-server >/dev/null 2>&1 || true
		fi
		sleep 1
	done
	err "ADB não autorizou. Saída: ${out:-sem resposta}"
	return 1
}

wait_android_boot() {
	local i
	for i in $(seq 1 90); do
		if [[ "$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
			return 0
		fi
		sleep 2
	done
	return 1
}

# ---------------------------------------------------------------------------
# Correção de rede (UFW/iptables/NAT) — regras independentes da WAN
# ---------------------------------------------------------------------------
write_net_fix() {
	install -d -m 0755 /usr/local/lib/waydroid
	cat > /usr/local/lib/waydroid/net-fix <<'NETFIX'
#!/usr/bin/env bash
# Reaplica as regras de rede do Waydroid sem depender do nome da interface WAN.
# Idempotente: pode rodar quantas vezes quiser (boot, troca de rede, timer).
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

log() { printf '[waydroid-net] %s\n' "$*"; }

WAN_IF="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
sysctl -qw net.ipv4.ip_forward=1 || true

# Só age quando o Waydroid está de pé.
[[ -e /sys/class/net/waydroid0 ]] || exit 0
command -v iptables >/dev/null 2>&1 || exit 0

changed=0
ensure() {
	local table="$1"; shift
	if ! iptables -w 5 -t "$table" -C "$@" >/dev/null 2>&1; then
		if iptables -w 5 -t "$table" -I "$@" >/dev/null 2>&1; then
			changed=1
		fi
	fi
}

# Entrada: DHCP e DNS vindos do container
ensure filter INPUT -i waydroid0 -p udp --dport 67 -j ACCEPT
ensure filter INPUT -i waydroid0 -p tcp --dport 67 -j ACCEPT
ensure filter INPUT -i waydroid0 -p udp --dport 53 -j ACCEPT
ensure filter INPUT -i waydroid0 -p tcp --dport 53 -j ACCEPT

# Forward: NÃO depende da WAN. Cobre Ethernet, Wi-Fi, USB tethering e VPN.
ensure filter FORWARD -i waydroid0 -j ACCEPT
ensure filter FORWARD -o waydroid0 -j ACCEPT

# NAT
if ! iptables -w 5 -t nat -C POSTROUTING \
	-s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE >/dev/null 2>&1; then
	if iptables -w 5 -t nat -A POSTROUTING \
		-s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE >/dev/null 2>&1; then
		changed=1
	fi
fi

# MTU/VPN: evita download travado por MSS grande demais
ensure mangle FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Checksum do DHCP (alguns setups perdem o lease sem isso)
ensure mangle POSTROUTING -o waydroid0 -p udp --dport 68 -j CHECKSUM --checksum-fill

# UFW: regras genéricas, sem citar a WAN. Persistem em /etc/ufw/user.rules.
if command -v ufw >/dev/null 2>&1; then
	if ufw status 2>/dev/null | grep -q '^Status: active'; then
		ufw route allow in on waydroid0 comment 'Waydroid outbound' >/dev/null 2>&1 || true
		ufw route allow out on waydroid0 comment 'Waydroid return' >/dev/null 2>&1 || true
		if [[ -n "$WAN_IF" ]]; then
			# Mantém também a regra específica da WAN atual (compatibilidade).
			ufw route allow in on waydroid0 out on "$WAN_IF" comment 'Waydroid outbound' >/dev/null 2>&1 || true
			ufw route allow in on "$WAN_IF" out on waydroid0 comment 'Waydroid return' >/dev/null 2>&1 || true
		fi
	fi
fi

if (( changed )); then
	log "regras reaplicadas (WAN=${WAN_IF:-desconhecida})"
fi
NETFIX
	chmod 0755 /usr/local/lib/waydroid/net-fix
}

write_persistence() {
	# 1) NetworkManager: reaplica quando qualquer interface sobe/desce/VPN muda.
	install -d -m 0755 /etc/NetworkManager/dispatcher.d
	cat > /etc/NetworkManager/dispatcher.d/90-waydroid-net-fix <<'DISPATCH'
#!/bin/sh
# Reaplica as regras do Waydroid quando a rede muda (WAN/VPN/USB tethering).
[ -x /usr/local/lib/waydroid/net-fix ] || exit 0
case "$2" in
	up|down|connectivity-change|vpn-up|vpn-down|dhcp4-change|dhcp6-change) ;;
	*) exit 0 ;;
esac
exec /usr/bin/flock -n /run/waydroid-net-fix.lock /usr/local/lib/waydroid/net-fix >/dev/null 2>&1
DISPATCH
	chmod 0755 /etc/NetworkManager/dispatcher.d/90-waydroid-net-fix

	# 2) Serviço: sem limite de tentativas (o path unit pode disparar várias vezes).
	cat > /etc/systemd/system/waydroid-net-fix.service <<'UNIT'
[Unit]
Description=Correções de rede/firewall do Waydroid
After=network-online.target NetworkManager.service ufw.service waydroid-container.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -w 10 /run/waydroid-net-fix.lock /usr/local/lib/waydroid/net-fix
UNIT

	# 3) Timer: rede de segurança. Se o ufw recarregar ou a WAN mudar sem
	#    dispatcher, no máximo em 3 min as regras voltam.
	cat > /etc/systemd/system/waydroid-net-fix.timer <<'TIMER'
[Unit]
Description=Reaplica periodicamente as regras de rede do Waydroid

[Timer]
OnBootSec=45s
OnUnitActiveSec=3min
AccuracySec=30s
Unit=waydroid-net-fix.service

[Install]
WantedBy=timers.target
TIMER

	systemctl daemon-reload >/dev/null 2>&1 || true

	# O path unit antigo (PathExists=/sys/class/net/waydroid0) re-dispara o
	# serviço em loop enquanto a interface existe. O timer + dispatcher já
	# cobrem a reaplicação; por isso o path é desativado e removido.
	systemctl disable --now waydroid-net-fix.path >/dev/null 2>&1 || true
	rm -f /etc/systemd/system/waydroid-net-fix.path
	systemctl daemon-reload >/dev/null 2>&1 || true

	systemctl enable --now waydroid-net-fix.timer >/dev/null 2>&1 || true
}

show_network_diagnosis() {
	printf '  WAN atual:            %s\n' "$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
	printf '  ip_forward:           %s\n' "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo '?')"
	printf '  waydroid0:            %s\n' "$(ip -4 -br addr show waydroid0 2>/dev/null || echo 'ausente')"
	printf '  ufw:                  %s\n' "$(systemctl is-active ufw 2>/dev/null || echo 'inativo')"
	printf '  FORWARD policy:       %s\n' \
		"$(sed -n 's/^DEFAULT_FORWARD_POLICY=//p' /etc/default/ufw 2>/dev/null | tr -d '"' || echo '?')"
	printf '  regras waydroid ufw:  %s\n' \
		"$(grep -c -- '-A ufw-user-forward .*waydroid0' /etc/ufw/user.rules 2>/dev/null || echo 0)"
}

repair_network() {
	step "Rede: UFW/iptables/NAT"
	show_network_diagnosis

	if [[ $AM_ROOT -ne 1 ]]; then
		warn "Sem root: não aplico regras de firewall. Rode com sudo."
		return 1
	fi

	write_net_fix
	if /usr/local/lib/waydroid/net-fix; then
		ok "regras de rede aplicadas"
	else
		warn "net-fix retornou erro; veja /usr/local/lib/waydroid/net-fix"
	fi

	if [[ $PERSIST -eq 1 ]]; then
		write_persistence
		ok "persistência instalada (NetworkManager dispatcher + timer 3min)"
	else
		warn "--no-persist: correção não sobreviverá a reboot/troca de rede"
	fi

	# Mostra quantas regras de forward o UFW tem agora.
	printf '  regras waydroid ufw:  %s\n' \
		"$(grep -c -- '-A ufw-user-forward .*waydroid0' /etc/ufw/user.rules 2>/dev/null || echo 0)"
}

verify_tcp_from_android() {
	local url="${1:-https://www.google.com/generate_204}"
	local i code
	for i in $(seq 1 30); do
		code="$(adb_cmd shell "curl -sS -m 8 -o /dev/null -w '%{http_code}' '$url'" 2>/dev/null | tr -d '\r' || true)"
		if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
			return 0
		fi
		sleep 2
	done
	return 1
}

# ---------------------------------------------------------------------------
# Apps
# ---------------------------------------------------------------------------
focus_now() {
	adb_cmd shell dumpsys window 2>/dev/null | grep -m1 'mCurrentFocus' || true
}

launch_nio() {
	step "Nio Player (com.nio.smart.player)"
	if ! adb_cmd shell pm list packages 2>/dev/null | grep -q 'package:com.nio.smart.player'; then
		err "Pacote com.nio.smart.player não está instalado."
		return 1
	fi

	# Cold start é obrigatório: o auto-login só roda na inicialização.
	adb_cmd shell am force-stop com.nio.smart.player >/dev/null 2>&1 || true
	sleep 1
	adb_cmd shell am start -n com.nio.smart.player/com.fusion.SplashActivity \
		>/dev/null 2>&1 || true

	local i f
	for i in $(seq 1 60); do
		f="$(focus_now)"
		if [[ "$f" == *'com.nio.smart.player/com.fusion.dashboard.DashboardActivity'* ]]; then
			ok "Nio abriu no dashboard"
			return 0
		fi
		sleep 1
	done

	# Uma segunda tentativa: às vezes o primeiro start pega rede ainda inválida.
	log "Nio não chegou ao dashboard; tentando mais uma vez..."
	adb_cmd shell am force-stop com.nio.smart.player >/dev/null 2>&1 || true
	sleep 2
	adb_cmd shell am start -n com.nio.smart.player/com.fusion.SplashActivity \
		>/dev/null 2>&1 || true
	for i in $(seq 1 45); do
		f="$(focus_now)"
		if [[ "$f" == *'com.nio.smart.player/com.fusion.dashboard.DashboardActivity'* ]]; then
			ok "Nio abriu no dashboard (2ª tentativa)"
			return 0
		fi
		sleep 1
	done

	err "Nio não chegou ao dashboard. Foco atual: ${f:-?}"
	adb_cmd logcat -d -t 400 2>/dev/null \
		| grep -iE 'nio|fusion|SocketTimeout|ConnectException|UnknownHost|licence|FATAL|ANR' \
		| tail -20 || true
	return 1
}

launch_stv() {
	step "STV (com.bx.livf)"
	if ! adb_cmd shell pm list packages 2>/dev/null | grep -q 'package:com.bx.livf'; then
		err "Pacote com.bx.livf não está instalado."
		return 1
	fi

	adb_cmd shell am force-stop com.bx.livf >/dev/null 2>&1 || true
	sleep 1
	adb_cmd shell am start -n com.bx.livf/com.bx.live.activity.IndexActivity \
		>/dev/null 2>&1 || true

	local i xml text f
	for i in $(seq 1 45); do
		sleep 2
		adb_cmd shell uiautomator dump /sdcard/stv_ui.xml >/dev/null 2>&1 || true
		xml="$(adb_cmd shell cat /sdcard/stv_ui.xml 2>/dev/null || true)"
		text="$(printf '%s' "$xml" | grep -oE 'text="[^"]*"' | grep -v 'text=""' || true)"
		if printf '%s' "$text" | grep -qiE 'ABERTOS|NOT[IÍ]CIAS|TODOS|CANAIS|FAVORITOS|VARIEDADES|FILMES|ESPORTE|INFANTIL|4K|PLAYBACK'; then
			ok "STV abriu (lista de canais carregada)"
			return 0
		fi
	done

	# Fallback: se está em foco e o processo vive, o app abriu; a lista pode
	# apenas estar demorando na tradução ARM.
	f="$(focus_now)"
	if [[ "$f" == *'com.bx.livf'* ]] && adb_cmd shell pidof com.bx.livf >/dev/null 2>&1; then
		warn "STV está aberto e em foco, mas não confirmei a lista de canais."
		warn "Se continuar no logo, aguarde ~20s ou abra de novo pelo ícone."
		return 0
	fi

	err "STV não abriu. Foco atual: ${f:-?}"
	adb_cmd logcat -d -t 500 2>/dev/null \
		| grep -iE 'bx\.livf|SocketTimeout|ConnectException|UnknownHost|AndroidRuntime|FATAL|ANR' \
		| tail -20 || true
	return 1
}

verify_nio_process() {
	adb_cmd shell pidof com.nio.smart.player >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Diagnóstico (--check)
# ---------------------------------------------------------------------------
check_mode() {
	printf '%sWaydroid — diagnóstico dos apps (Nio + STV)%s\n' "$C_BOLD" "$C_RESET"

	step "Host"
	printf '  Usuário:              %s (uid %s)\n' "$TARGET_USER" "$TARGET_UID"
	printf '  Waydroid:             %s\n' "$(waydroid --version 2>/dev/null || echo '?')"
	show_network_diagnosis

	step "Sessão"
	waydroid_status | sed 's/^/  /'

	local ip; ip="$(waydroid_ip)"
	if [[ -z "$ip" ]]; then
		warn "Sem IP; sessão não está rodando."
		return 1
	fi

	if ! ensure_adb; then
		return 1
	fi
	if ! connect_adb "$ip"; then
		return 1
	fi

	step "Android"
	printf '  abilist:              %s\n' "$(adb_cmd shell getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r' || true)"
	printf '  native bridge:        %s\n' "$(adb_cmd shell getprop ro.dalvik.vm.native.bridge 2>/dev/null | tr -d '\r' || true)"
	printf '  boot_completed:       %s\n' "$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
	printf '  pacotes:              %s\n' \
		"$(adb_cmd shell pm list packages 2>/dev/null | grep -E 'com\.nio|com\.bx' | tr '\n' ' ' || true)"
	printf '  foco:                 %s\n' "$(focus_now | sed 's/.*mCurrentFocus=//')"

	step "Testes de rede dentro do Android"
	local url code
	for url in \
		https://www.google.com/generate_204 \
		http://bnewsc.top/player_api.php \
		https://nio.gerenciapro.top/bnsc/api/; do
		code="$(adb_cmd shell "curl -sS -m 8 -o /dev/null -w '%{http_code}' '$url'" 2>/dev/null | tr -d '\r' || true)"
		printf '  %-48s HTTP %s\n' "$url" "${code:-erro}"
	done

	step "Conclusão"
	if [[ "$(adb_cmd shell "curl -sS -m 8 -o /dev/null -w '%{http_code}' https://www.google.com/generate_204" 2>/dev/null | tr -d '\r' || true)" =~ ^[23][0-9][0-9]$ ]]; then
		ok "TCP de saída OK."
	else
		err "TCP de saída BLOQUEADO (UFW/FORWARD). Rode: sudo $SELF"
	fi
	printf '\n'
}

# ---------------------------------------------------------------------------
# Fluxo principal
# ---------------------------------------------------------------------------
main() {
	printf '%sWaydroid — correção dos apps Nio Player + STV%s\n' "$C_BOLD" "$C_RESET"

	ensure_container || true
	if ! ensure_session; then
		die "Sessão do Waydroid não está rodando; não é possível abrir os apps."
	fi

	local ip; ip="$(waydroid_ip)"
	[[ -n "$ip" ]] || die "Não consegui obter o IP do container."
	log "IP do container: $ip"

	if ! ensure_adb; then
		die "ADB indisponível; não é possível validar/abrir os apps."
	fi
	connect_adb "$ip" || die "ADB não autorizou."
	wait_android_boot || warn "Android ainda não concluiu o boot; seguindo mesmo assim."

	step "ABI / tradução ARM"
	local abilist bridge
	abilist="$(adb_cmd shell getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r' || true)"
	bridge="$(adb_cmd shell getprop ro.dalvik.vm.native.bridge 2>/dev/null | tr -d '\r' || true)"
	printf '  abilist:              %s\n' "$abilist"
	printf '  native bridge:        %s\n' "$bridge"
	if [[ "$abilist" == *armeabi-v7a* ]]; then
		ok "tradução ARM presente"
	else
		warn "Sem armeabi-v7a: o STV (ARM) não vai abrir."
		warn "Instale libhoudini/libndk: cd waydroid_script && sudo venv/bin/python3 main.py install libndk"
	fi

	repair_network || warn "Correção de rede não aplicada por completo."

	step "Validando TCP de dentro do Android"
	if verify_tcp_from_android; then
		ok "TCP de saída funcionando"
		# O Android revalida a rede; dá um instante para os apps enxergarem.
		sleep 2
	else
		err "TCP continua bloqueado. Diagnóstico:"
		show_network_diagnosis
		err "Rode 'ufw status verbose' e confira as regras de FORWARD."
		exit 1
	fi

	local nio_ok=0 stv_ok=0
	launch_nio && nio_ok=1 || true
	launch_stv && stv_ok=1 || true

	if (( nio_ok )); then
		verify_nio_process && ok "Nio continua rodando em segundo plano" \
			|| warn "Nio saiu do dashboard/processo depois do STV."
	fi

	printf '\n%s================================================================%s\n' "$C_GREEN" "$C_RESET"
	if (( nio_ok && stv_ok )); then
		printf '%s  RESULTADO: Nio e STV abriram%s\n' "$C_BOLD" "$C_RESET"
	else
		printf '%s  RESULTADO: correção parcial%s\n' "$C_YELLOW" "$C_RESET"
		(( nio_ok )) || printf '   - Nio: FALHOU\n'
		(( stv_ok )) || printf '   - STV: FALHOU\n'
	fi
	printf '%s================================================================%s\n' "$C_GREEN" "$C_RESET"
	printf '  Foco atual: %s\n' "$(focus_now | sed 's/.*mCurrentFocus=//')"
	printf '\n  Para abrir de novo manualmente:\n'
	printf '    waydroid app launch com.nio.smart.player\n'
	printf '    waydroid app launch com.bx.livf\n'
	printf '\n  Diagnóstico a qualquer momento:\n'
	printf '    sudo %s --check\n' "$SELF"
	printf '\n'
}

case "$MODE" in
	check) check_mode ;;
	fix)   main ;;
esac
