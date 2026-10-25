#!/usr/bin/env bash
# =============================================================================
#  cleanup_waydroid.sh
#
#  Remove uma instalação do Waydroid para permitir um setup limpo.
#
#  O que remove:
#    - sessão do usuário e serviço waydroid-session
#    - container, binderfs, unidades e drop-ins criados pelo setup_waydroid.sh
#    - imagens, dados Android, configuração e logs
#    - regras de firewall/NAT específicas do Waydroid
#    - scripts auxiliares em /usr/local/lib/waydroid
#
#  O pacote waydroid NÃO é removido por padrão. Use --remove-package se quiser.
#
#  Uso:
#    ./cleanup_waydroid.sh --check              # só mostra o que existe
#    sudo ./cleanup_waydroid.sh                 # remove (pede confirmação)
#    sudo ./cleanup_waydroid.sh --yes           # sem confirmação
#    sudo ./cleanup_waydroid.sh --remove-package --yes
# =============================================================================

set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ORIG_ARGS=("$@")

MODE="cleanup"
ASSUME_YES=0
REMOVE_PACKAGE=0

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_BLUE=$'\033[1;34m'
    C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
    C_CYAN=$'\033[1;36m'
else
    C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

log()  { printf '%s[cleanup]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
die()  { err "$*"; exit 1; }

trap 'printf "\n%s[ERRO]%s comando falhou (rc=%s): %s\n" "$C_RED" "$C_RESET" "$?" "$BASH_COMMAND" >&2' ERR

usage() {
    sed -n '2,23p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)          MODE="check" ;;
        --yes|-y)         ASSUME_YES=1 ;;
        --remove-package) REMOVE_PACKAGE=1 ;;
        -h|--help)        usage ;;
        *) die "Opção desconhecida: $1 (use --help)" ;;
    esac
    shift
done

AM_ROOT=0
[[ ${EUID} -eq 0 ]] && AM_ROOT=1

if [[ "$MODE" != "check" && $AM_ROOT -eq 0 ]]; then
    command -v sudo >/dev/null || die "sudo não encontrado; rode como root."
    log "Elevando privilégios com sudo..."
    exec sudo -E bash "$SCRIPT_PATH" "${ORIG_ARGS[@]}"
fi

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
    local user_env=(
        env
        HOME="$TARGET_HOME"
        USER="$TARGET_USER"
        LOGNAME="$TARGET_USER"
        XDG_RUNTIME_DIR="$TARGET_RUNTIME"
        DBUS_SESSION_BUS_ADDRESS="unix:path=${TARGET_RUNTIME}/bus"
        PATH="/usr/local/bin:/usr/bin:/bin"
    )
    if [[ $AM_ROOT -eq 1 ]]; then
        runuser -u "$TARGET_USER" -- "${user_env[@]}" "$@"
    elif [[ "$TARGET_USER" == "$(id -un)" ]]; then
        "${user_env[@]}" "$@"
    else
        die "Sem root só é possível executar como o usuário atual."
    fi
}

state() {
    local unit="$1"
    printf '%s (ativo: %s, enabled: %s)\n' \
        "$unit" \
        "$(systemctl is-active "$unit" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
}

size_of() {
    local path="$1" out=""
    if [[ ! -e "$path" ]]; then
        printf 'ausente'
        return 0
    fi
    out="$(du -sh "$path" 2>/dev/null | awk 'NR==1{print $1}' || true)"
    printf '%s' "${out:-sem acesso}"
}

check_mode() {
    detect_target_user

    printf '%sLimpeza do Waydroid — diagnóstico%s\n' "$C_BOLD" "$C_RESET"
    printf 'Usuário do desktop: %s (uid %s)\n' "$TARGET_USER" "$TARGET_UID"

    step "Pacote"
    if command -v waydroid >/dev/null 2>&1; then
        printf '  waydroid: %s\n' "$(waydroid --version 2>/dev/null || echo '?')"
        pacman -Qo "$(command -v waydroid)" 2>/dev/null || true
    else
        printf '  waydroid: não instalado\n'
    fi

    step "Serviços"
    state waydroid-container.service
    state waydroid-binderfs.service
    state dev-binderfs.mount
    state waydroid-net-fix.path
    state waydroid-net-fix.service
    printf '  waydroid-session.service (user): ativo: %s, enabled: %s\n' \
        "$(run_as_user systemctl --user is-active waydroid-session.service 2>/dev/null || true)" \
        "$(run_as_user systemctl --user is-enabled waydroid-session.service 2>/dev/null || true)"

    step "Dados"
    printf '  /var/lib/waydroid:              %s\n' "$(size_of /var/lib/waydroid)"
    printf '  /var/lib/waydroid-setup:        %s\n' "$(size_of /var/lib/waydroid-setup)"
    printf '  %s/.local/share/waydroid: %s\n' "$TARGET_HOME" "$(size_of "$TARGET_HOME/.local/share/waydroid")"
    printf '  imagens:                        %s\n' "$(size_of /var/lib/waydroid/images)"

    step "Binder"
    for n in binder vndbinder hwbinder; do
        if [[ -L "/dev/${n}" ]]; then
            printf '  /dev/%s -> %s (symlink)\n' "$n" "$(readlink "/dev/${n}")"
        elif [[ -c "/dev/${n}" ]]; then
            printf '  /dev/%s (device real)\n' "$n"
        else
            printf '  /dev/%s ausente\n' "$n"
        fi
    done
    if mountpoint -q /dev/binderfs 2>/dev/null; then
        printf '  /dev/binderfs montado\n'
    else
        printf '  /dev/binderfs não montado\n'
    fi

    step "Rede"
    if command -v ufw >/dev/null 2>&1; then
        ufw status 2>/dev/null | grep -i waydroid || printf '  sem regras UFW do Waydroid\n'
    fi
    iptables -S FORWARD 2>/dev/null | grep -i waydroid \
        || printf '  sem regras iptables FORWARD do Waydroid (ou sem root)\n'
    iptables -t nat -S POSTROUTING 2>/dev/null | grep '192.168.240.0/24' \
        || printf '  sem NAT do Waydroid (ou sem root)\n'

    step "Arquivos auxiliares"
    for p in \
        /usr/local/lib/waydroid \
        /etc/systemd/system/waydroid-binderfs.service \
        /etc/systemd/system/dev-binderfs.mount \
        /etc/systemd/system/waydroid-net-fix.service \
        /etc/systemd/system/waydroid-net-fix.path \
        /etc/systemd/system/waydroid-container.service.d/10-binderfs.conf \
        /etc/sysctl.d/99-waydroid.conf; do
        [[ -e "$p" ]] && printf '  %s\n' "$p"
    done

    step "Próximo passo"
    printf '  Para apagar tudo: sudo %s --yes\n' "$SCRIPT_PATH"
    printf '  Para remover também o pacote: sudo %s --remove-package --yes\n\n' "$SCRIPT_PATH"
}

cleanup_mode() {
    detect_target_user

    if [[ $ASSUME_YES -eq 0 ]]; then
        warn "Isto apaga imagens, dados Android, configuração e regras de rede do Waydroid."
        warn "O pacote waydroid será mantido, a menos que você use --remove-package."
        printf '\n'
        read -rp "Digite APAGAR para continuar: " answer || true
        [[ "$answer" == "APAGAR" ]] || die "Cancelado."
    fi

    step "Parando sessão do usuário"
    if [[ -d "$TARGET_RUNTIME" ]]; then
        run_as_user systemctl --user stop waydroid-session.service 2>/dev/null || true
        run_as_user systemctl --user disable waydroid-session.service 2>/dev/null || true
    fi
    run_as_user timeout 15 waydroid session stop >/dev/null 2>&1 || true
    ok "Sessão parada."

    step "Parando serviços do sistema"
    systemctl stop waydroid-net-fix.path waydroid-net-fix.service 2>/dev/null || true
    systemctl disable waydroid-net-fix.path 2>/dev/null || true
    systemctl stop waydroid-container 2>/dev/null || true
    systemctl disable waydroid-container 2>/dev/null || true
    systemctl stop waydroid-binderfs.service 2>/dev/null || true
    systemctl disable waydroid-binderfs.service 2>/dev/null || true
    systemctl stop dev-binderfs.mount 2>/dev/null || true
    ok "Serviços parados."

    step "Removendo unidades e scripts auxiliares"
    rm -f /etc/systemd/system/waydroid-binderfs.service
    rm -f /etc/systemd/system/dev-binderfs.mount
    rm -f /etc/systemd/system/waydroid-net-fix.service
    rm -f /etc/systemd/system/waydroid-net-fix.path
    rm -f /etc/systemd/system/waydroid-container.service.d/10-binderfs.conf
    rmdir /etc/systemd/system/waydroid-container.service.d 2>/dev/null || true
    rm -rf /usr/local/lib/waydroid
    rm -f /etc/sysctl.d/99-waydroid.conf
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true
    ok "Unidades removidas."

    step "Removendo regras de firewall/NAT"
    if command -v ufw >/dev/null 2>&1; then
        mapfile -t ufw_numbers < <(
            ufw status numbered 2>/dev/null \
                | grep -i waydroid \
                | sed -n 's/^\[ *\([0-9]\+\)\].*/\1/p' \
                | sort -rn
        )
        for n in "${ufw_numbers[@]:-}"; do
            [[ -n "$n" ]] || continue
            ufw --force delete "$n" >/dev/null 2>&1 || true
        done
    fi

    remove_ipt() {
        local table="$1"; shift
        while iptables -w 5 -t "$table" -C "$@" 2>/dev/null; do
            iptables -w 5 -t "$table" -D "$@" 2>/dev/null || break
        done
    }

    remove_ipt filter FORWARD -i waydroid0 -j ACCEPT
    remove_ipt filter FORWARD -o waydroid0 -j ACCEPT
    remove_ipt filter INPUT -i waydroid0 -p udp --dport 67 -j ACCEPT
    remove_ipt filter INPUT -i waydroid0 -p tcp --dport 67 -j ACCEPT
    remove_ipt filter INPUT -i waydroid0 -p udp --dport 53 -j ACCEPT
    remove_ipt filter INPUT -i waydroid0 -p tcp --dport 53 -j ACCEPT
    remove_ipt nat POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE
    remove_ipt mangle FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    remove_ipt mangle POSTROUTING -o waydroid0 -p udp --dport 68 -j CHECKSUM --checksum-fill
    ok "Regras removidas."

    step "Parando rede do Waydroid"
    if [[ -x /usr/lib/waydroid/data/scripts/waydroid-net.sh ]]; then
        /usr/lib/waydroid/data/scripts/waydroid-net.sh stop >/dev/null 2>&1 || true
    fi
    rm -rf /run/waydroid-lxc
    rm -f /var/lib/misc/dnsmasq.waydroid0.leases
    ok "Rede parada."

    step "Removendo binderfs"
    for n in binder vndbinder hwbinder; do
        if [[ -L "/dev/${n}" ]]; then
            rm -f "/dev/${n}"
        fi
    done
    for old in anbox-binder anbox-vndbinder anbox-hwbinder; do
        [[ -L "/dev/${old}" ]] && rm -f "/dev/${old}"
    done
    if mountpoint -q /dev/binderfs 2>/dev/null; then
        umount /dev/binderfs 2>/dev/null || umount -l /dev/binderfs 2>/dev/null || true
    fi
    rmdir /dev/binderfs 2>/dev/null || true
    ok "Binderfs removido."

    step "Apagando dados"
    if mountpoint -q /var/lib/waydroid/rootfs 2>/dev/null; then
        umount -R /var/lib/waydroid/rootfs 2>/dev/null || true
    fi
    for m in \
        /var/lib/waydroid/rootfs/vendor/waydroid.prop \
        /var/lib/waydroid/rootfs/vendor \
        /var/lib/waydroid/rootfs; do
        if mountpoint -q "$m" 2>/dev/null; then
            umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
        fi
    done
    rm -rf /var/lib/waydroid
    rm -rf /var/lib/waydroid-setup
    rm -f /var/log/waydroid-setup.log
    rm -f /tmp/waydroid-session.log
    rm -f /tmp/gservices.*.db /tmp/gservices.*.db-wal /tmp/gservices.*.db-shm
    rm -f /var/tmp/waydroid-*.zip /tmp/waydroid-*.zip
    rm -rf "$TARGET_HOME/.local/share/waydroid"
    rm -rf "$TARGET_HOME/.cache/waydroid"
    rm -rf "$TARGET_HOME/.config/waydroid"
    rm -f "$TARGET_HOME/.config/systemd/user/waydroid-session.service"
    run_as_user systemctl --user daemon-reload >/dev/null 2>&1 || true
    ok "Dados apagados."

    if [[ $REMOVE_PACKAGE -eq 1 ]]; then
        step "Removendo pacote waydroid"
        for p in waydroid waydroid-git; do
            if pacman -Qq "$p" >/dev/null 2>&1; then
                pacman -Rns --noconfirm "$p" || warn "Falha ao remover $p; remova manualmente."
            fi
        done
    else
        log "Pacote waydroid mantido; o setup reinstala se necessário."
    fi

    printf '\n'
    ok "Limpeza concluída. Rode o setup novamente:"
    printf '  sudo %s\n\n' "$(dirname "$SCRIPT_PATH")/setup_waydroid.sh"
}

case "$MODE" in
    check)   check_mode ;;
    cleanup) cleanup_mode ;;
esac
