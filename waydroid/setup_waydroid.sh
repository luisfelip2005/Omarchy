#!/usr/bin/env bash
# =============================================================================
#  setup_waydroid.sh
#
#  Setup completo do Waydroid com Google Play Store em Omarchy/Arch Linux.
#
#  O que este script faz:
#    1. Verifica o ambiente (Arch/Omarchy, kernel, Wayland, espaço em disco).
#    2. Instala dependências que estiverem faltando.
#    3. Configura binderfs nativo (Rust binder) via systemd, sem DKMS.
#    4. Baixa/inicializa a imagem oficial LineageOS 20 GAPPS.
#    5. Corrige rede/firewall (ufw + iptables-nft + NAT + ip_forward).
#    6. Cria um serviço de sessão do usuário e inicia o Waydroid.
#    7. Obtém o Android ID e orienta a certificação da Play Store.
#
#  Uso:
#    ./setup_waydroid.sh --check          # só diagnostica, não altera nada
#    sudo ./setup_waydroid.sh             # setup completo
#    sudo ./setup_waydroid.sh --certify   # certificar Play Store depois
#    sudo ./setup_waydroid.sh --verify    # diagnóstico da instalação
#    sudo ./setup_waydroid.sh --autostart # iniciar Waydroid no login
#
#  Opções:
#    --force-images     Rebaixa as imagens GAPPS (apaga as atuais)
#    --skip-images      Não inicializa/baixa imagens
#    --no-start         Não inicia a sessão/UI ao final
#    --no-network-fix   Não mexe em firewall/NAT
#    --no-certify       Não oferece a certificação ao final
#    -y, --yes          Não pede confirmações
#    -h, --help         Ajuda
# =============================================================================

set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ORIG_ARGS=("$@")

WAYDROID_DIR="/var/lib/waydroid"
IMAGES_DIR="${WAYDROID_DIR}/images"
STATE_DIR="/var/lib/waydroid-setup"
LOG_FILE="/var/log/waydroid-setup.log"

MODE="setup"
DO_IMAGES=1
FORCE_IMAGES=0
DO_START=1
DO_NETWORK=1
DO_CERTIFY=1
AUTOSTART=0
ASSUME_YES=0

# ---------------------------------------------------------------------------
# Cores / log
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_BLUE=$'\033[1;34m'
    C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'
    C_CYAN=$'\033[1;36m'
else
    C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

log()  { printf '%s[waydroid]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
die()  { err "$*"; exit 1; }

trap 'printf "\n%s[ERRO]%s comando falhou (rc=%s): %s\n" "$C_RED" "$C_RESET" "$?" "$BASH_COMMAND" >&2' ERR

usage() {
    sed -n '2,31p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)         MODE="check" ;;
        --verify)        MODE="verify" ;;
        --certify)       MODE="certify" ;;
        --setup)         MODE="setup" ;;
        --force-images)  FORCE_IMAGES=1 ;;
        --skip-images)   DO_IMAGES=0 ;;
        --no-start)      DO_START=0 ;;
        --no-network-fix) DO_NETWORK=0 ;;
        --no-certify)    DO_CERTIFY=0 ;;
        --autostart)     AUTOSTART=1; MODE="autostart" ;;
        -y|--yes)        ASSUME_YES=1 ;;
        -h|--help)       usage ;;
        *) die "Opção desconhecida: $1 (use --help)" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Root / usuário-alvo
# ---------------------------------------------------------------------------
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
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_RUNTIME="/run/user/${TARGET_UID}"
    TARGET_DISPLAY="${DISPLAY:-:0}"
}

detect_wayland() {
    local envout=""
    if [[ -d "$TARGET_RUNTIME" ]]; then
        if [[ $AM_ROOT -eq 1 ]]; then
            envout="$(runuser -u "$TARGET_USER" -- \
                env XDG_RUNTIME_DIR="$TARGET_RUNTIME" \
                    DBUS_SESSION_BUS_ADDRESS="unix:path=${TARGET_RUNTIME}/bus" \
                    systemctl --user show-environment 2>/dev/null || true)"
        elif [[ "$TARGET_USER" == "$(id -un)" ]]; then
            envout="$(env XDG_RUNTIME_DIR="$TARGET_RUNTIME" \
                    DBUS_SESSION_BUS_ADDRESS="unix:path=${TARGET_RUNTIME}/bus" \
                    systemctl --user show-environment 2>/dev/null || true)"
        fi
    fi
    TARGET_WAYLAND_DISPLAY="$(sed -n 's/^WAYLAND_DISPLAY=//p' <<<"$envout" | head -n1)"
    if [[ -z "$TARGET_WAYLAND_DISPLAY" ]]; then
        TARGET_WAYLAND_DISPLAY="$(find "$TARGET_RUNTIME" -maxdepth 1 -type s \
            -name 'wayland-*' -printf '%f\n' 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$TARGET_WAYLAND_DISPLAY" && -n "${WAYLAND_DISPLAY:-}" ]]; then
        TARGET_WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
    fi
    GRAPHICAL=0
    if [[ -n "$TARGET_WAYLAND_DISPLAY" ]]; then
        if [[ "$TARGET_WAYLAND_DISPLAY" = /* ]]; then
            [[ -S "$TARGET_WAYLAND_DISPLAY" ]] && GRAPHICAL=1
        else
            [[ -S "${TARGET_RUNTIME}/${TARGET_WAYLAND_DISPLAY}" ]] && GRAPHICAL=1
        fi
    fi
}

run_as_user() {
    local user_env=(
        env
        HOME="$TARGET_HOME"
        USER="$TARGET_USER"
        LOGNAME="$TARGET_USER"
        XDG_RUNTIME_DIR="$TARGET_RUNTIME"
        DBUS_SESSION_BUS_ADDRESS="unix:path=${TARGET_RUNTIME}/bus"
        WAYLAND_DISPLAY="${TARGET_WAYLAND_DISPLAY:-}"
        DISPLAY="${TARGET_DISPLAY:-:0}"
        XDG_SESSION_TYPE=wayland
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

user_systemctl() {
    run_as_user systemctl --user "$@"
}

detect_target_user
detect_wayland

# ---------------------------------------------------------------------------
# Diagnóstico (--check) — não altera nada, não exige root
# ---------------------------------------------------------------------------
read_cfg() {
    local key="$1"
    [[ -f "${WAYDROID_DIR}/waydroid.cfg" ]] || return 1
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$/\1/p" \
        "${WAYDROID_DIR}/waydroid.cfg" | tail -n1
}

print_kernel_info() {
    local kconfig
    kconfig="/lib/modules/$(uname -r)/build/.config"
    local rust="não", binderfs="não"

    if [[ -r "$kconfig" ]] && grep -q '^CONFIG_ANDROID_BINDER_IPC_RUST=y' "$kconfig"; then
        rust="sim"
    fi
    if grep -qw binder /proc/filesystems 2>/dev/null; then
        binderfs="sim"
    fi

    printf '  Kernel:              %s\n' "$(uname -r)"
    printf '  Rust binder:         %s\n' "$rust"
    printf '  binderfs:            %s\n' "$binderfs"
    printf '  /dev/binder:         %s\n' "$(ls -l /dev/binder 2>/dev/null || echo 'ausente')"
    printf '  /dev/vndbinder:      %s\n' "$(ls -l /dev/vndbinder 2>/dev/null || echo 'ausente')"
    printf '  /dev/hwbinder:       %s\n' "$(ls -l /dev/hwbinder 2>/dev/null || echo 'ausente')"
}

check_mode() {
    section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }

    printf '%sWaydroid — diagnóstico do ambiente%s\n' "$C_BOLD" "$C_RESET"

    section "Sistema"
    printf '  Distro:              %s\n' "$(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}")"
    printf '  Arquitetura:         %s\n' "$(uname -m)"
    printf '  Sessão:              %s (%s), usuário %s\n' \
        "${XDG_SESSION_TYPE:-?}" "${XDG_CURRENT_DESKTOP:-?}" "$TARGET_USER"
    printf '  Wayland display:     %s (gráfico: %s)\n' \
        "${TARGET_WAYLAND_DISPLAY:-?}" "$([[ $GRAPHICAL -eq 1 ]] && echo sim || echo não)"
    printf '  Espaço em /var:      %s\n' "$(df -h /var/lib 2>/dev/null | awk 'NR==2{print $4}')"
    printf '  Secure Boot:         %s\n' \
        "$(od -An -tu1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | awk '{print ($6==1?"habilitado":"desabilitado")}' || echo 'desconhecido')"

    section "Kernel / Binder"
    print_kernel_info
    printf '  rust_devices:        %s\n' \
        "$(cat /sys/module/rust_binder/parameters/rust_devices 2>/dev/null || echo 'n/a')"

    section "Waydroid"
    if command -v waydroid >/dev/null; then
        printf '  Versão:              %s\n' "$(waydroid --version 2>/dev/null || echo '?')"
    else
        printf '  Versão:              não instalado\n'
    fi
    printf '  Serviço container:   %s\n' "$(systemctl is-active waydroid-container 2>/dev/null || true)"
    printf '  Sessão:              %s\n' \
        "$(run_as_user waydroid status 2>/dev/null | tr '\n' ' ' || echo 'indisponível')"
    printf '  Imagens:             %s\n' \
        "$([[ -s "${IMAGES_DIR}/system.img" && -s "${IMAGES_DIR}/vendor.img" ]] && echo presentes || echo ausentes)"
    printf '  system_ota:          %s\n' "$(read_cfg system_ota || echo '—')"
    printf '  Binder na config:    %s\n' "$(read_cfg binder || echo '—')"
    printf '  UFW:                 %s\n' "$(systemctl is-active ufw 2>/dev/null || echo inativo)"
    printf '  Política forward:    %s\n' \
        "$(sed -n 's/^DEFAULT_FORWARD_POLICY=//p' /etc/default/ufw 2>/dev/null | tr -d '"' || echo '?')"
    printf '  Backend iptables:    %s\n' "$(iptables --version 2>/dev/null || echo '?')"

    section "Rede"
    printf '  ip_forward:          %s\n' "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo '?')"
    printf '  Interface WAN:       %s\n' \
        "$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
    printf '  waydroid0:           %s\n' \
        "$(ip -br addr show waydroid0 2>/dev/null || echo 'ausente')"
    printf '  dnsmasq (waydroid):  %s\n' \
        "$([[ -f /run/waydroid-lxc/network_up ]] && echo ativo || echo inativo)"

    section "Próximos passos"
    if [[ ! -s "${IMAGES_DIR}/system.img" ]]; then
        printf '  Execute: sudo %s\n' "$SCRIPT_PATH"
    else
        printf '  Inicie:  waydroid show-full-ui   (ou pelo menu do desktop)\n'
        printf '  Certifique a Play Store: sudo %s --certify\n' "$SCRIPT_PATH"
    fi
    printf '\n'
}

# ---------------------------------------------------------------------------
# Setup — etapas
# ---------------------------------------------------------------------------
preflight() {
    step "Verificando ambiente"
    [[ -f /etc/os-release ]] || die "/etc/os-release não encontrado."
    if ! grep -qiE '^(ID|ID_LIKE)=.*(arch|omarchy)' /etc/os-release; then
        warn "Esta distro não parece Arch/Omarchy; o script usa pacman e pode falhar."
    fi
    command -v pacman >/dev/null || die "pacman não encontrado."
    [[ "$(uname -m)" == "x86_64" ]] || die "Somente x86_64 é suportado pelas imagens oficiais."

    local avail_kb
    avail_kb="$(df -Pk /var/lib | awk 'NR==2{print $4}')"
    if [[ -n "$avail_kb" && "$avail_kb" -lt 5242880 ]]; then
        die "Espaço insuficiente em /var/lib (precisa de ~5 GB livres)."
    fi

    if ! grep -qw binder /proc/filesystems; then
        warn "binderfs não aparece em /proc/filesystems."
        warn "Será tentado o fallback com binder_linux-dkms (AUR)."
    fi

    if [[ $GRAPHICAL -eq 0 ]]; then
        warn "Nenhum socket Wayland ativo detectado para $TARGET_USER."
        warn "O setup continuará, mas a sessão gráfica não será iniciada."
        DO_START=0
    fi

    if ! curl -fsS --max-time 10 https://ota.waydro.id/ >/dev/null 2>&1; then
        warn "Não foi possível alcançar ota.waydro.id. Verifique sua internet."
    fi

    ok "Ambiente: $(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}"), kernel $(uname -r)"
    ok "Usuário do desktop: $TARGET_USER (uid $TARGET_UID)"
    ok "Wayland: ${TARGET_WAYLAND_DISPLAY:-indisponível}"
}

install_packages() {
    step "Instalando dependências"
    local pkgs=(lxc dnsmasq python-gbinder libgbinder libglibutil mesa vulkan-radeon libglvnd sqlite)
    local missing=()

    for p in "${pkgs[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
    done

    if ((${#missing[@]})); then
        log "Pacotes ausentes: ${missing[*]}"
        pacman -S --needed --noconfirm "${missing[@]}"
    fi

    if ! command -v waydroid >/dev/null; then
        log "Instalando Waydroid do repositório extra..."
        pacman -S --needed --noconfirm waydroid
    fi

    if [[ ! -d /lib/modules/$(uname -r)/build ]]; then
        warn "Headers do kernel atual ausentes. O fallback DKMS não funcionaria."
        warn "Instale: sudo pacman -S linux-omarchy-headers"
    fi

    ok "Dependências instaladas."
}

setup_binderfs() {
    step "Configurando binderfs (Rust binder)"

    if ! grep -qw binder /proc/filesystems; then
        install_binder_dkms
        return 0
    fi

    install -d -m 0755 /usr/local/lib/waydroid

    cat > /usr/local/lib/waydroid/setup-binderfs <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
BINDERFS="/dev/binderfs"
log() { printf '[waydroid-binderfs] %s\n' "$*"; }

if [[ ! -e "${BINDERFS}/binder-control" ]]; then
    echo "binderfs não está montado em ${BINDERFS}" >&2
    exit 1
fi

# Se já existe um binder real (módulo DKMS), não substituir por symlink.
if [[ -e /dev/binder && ! -L /dev/binder ]]; then
    log "/dev/binder já é um device real; mantendo."
    exit 0
fi

python3 - "$BINDERFS" <<'PY'
import errno
import fcntl
import os
import struct
import sys

base = sys.argv[1]
NRBITS, TYPEBITS, SIZEBITS = 8, 8, 14
NRSHIFT = 0
TYPESHIFT = NRSHIFT + NRBITS
SIZESHIFT = TYPESHIFT + TYPEBITS
DIRSHIFT = SIZESHIFT + SIZEBITS

def ioc(direction, typ, nr, size):
    return (direction << DIRSHIFT) | (typ << TYPESHIFT) | (nr << NRSHIFT) | (size << SIZESHIFT)

BINDER_CTL_ADD = ioc(0x3, 98, 1, 264)  # _IOWR('b', 1, struct binderfs_device)

with open(os.path.join(base, "binder-control"), "rb") as ctl:
    for node in ("binder", "vndbinder", "hwbinder"):
        try:
            fcntl.ioctl(ctl.fileno(), BINDER_CTL_ADD,
                        struct.pack("256sII", node.encode(), 0, 0))
        except OSError as exc:
            if exc.errno != errno.EEXIST:
                raise
PY

for node in binder vndbinder hwbinder; do
    if [[ ! -c "${BINDERFS}/${node}" ]]; then
        echo "Falha: nó ${node} não foi criado em ${BINDERFS}" >&2
        exit 1
    fi
    chmod 0666 "${BINDERFS}/${node}"
    ln -sfn "${BINDERFS}/${node}" "/dev/${node}"
done

# Remove symlinks antigos criados pelo Waydroid em versões anteriores.
for old in anbox-binder anbox-vndbinder anbox-hwbinder; do
    if [[ -L "/dev/${old}" ]]; then
        rm -f "/dev/${old}"
    fi
done

log "nós criados: /dev/binder /dev/vndbinder /dev/hwbinder"
EOS
    chmod 0755 /usr/local/lib/waydroid/setup-binderfs

    cat > /etc/systemd/system/dev-binderfs.mount <<'EOS'
[Unit]
Description=Binderfs para o Waydroid
Before=waydroid-binderfs.service waydroid-container.service

[Mount]
What=binder
Where=/dev/binderfs
Type=binder
EOS

    cat > /etc/systemd/system/waydroid-binderfs.service <<'EOS'
[Unit]
Description=Aloca nós binderfs para o Waydroid
Requires=dev-binderfs.mount
BindsTo=dev-binderfs.mount
After=dev-binderfs.mount
Before=waydroid-container.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/waydroid/setup-binderfs
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOS

    install -d -m 0755 /etc/systemd/system/waydroid-container.service.d
    cat > /etc/systemd/system/waydroid-container.service.d/10-binderfs.conf <<'EOS'
[Unit]
Wants=waydroid-binderfs.service
After=waydroid-binderfs.service dev-binderfs.mount
EOS

    systemctl daemon-reload
    systemctl enable waydroid-binderfs.service
    systemctl restart waydroid-binderfs.service

    local n
    for n in binder vndbinder hwbinder; do
        [[ -c "/dev/${n}" ]] || die "Nó /dev/${n} não foi criado."
    done
    ok "binderfs ativo: /dev/binder -> $(readlink -f /dev/binder) ($(stat -Lc '%A' /dev/binder))"
}

install_binder_dkms() {
    warn "binderfs indisponível; usando binder_linux-dkms como fallback."
    command -v yay >/dev/null || die "yay não encontrado; instale binder_linux-dkms manualmente."

    run_as_user yay -S --needed --noconfirm binder_linux-dkms

    cat > /etc/modules-load.d/binder_linux.conf <<'EOS'
binder_linux
EOS
    cat > /etc/modprobe.d/binder_linux.conf <<'EOS'
options binder_linux devices="binder,vndbinder,hwbinder"
EOS
    modprobe binder_linux 2>/dev/null || true

    local n
    for n in binder vndbinder hwbinder; do
        [[ -e "/dev/${n}" ]] || die "Módulo binder_linux não criou /dev/${n}."
    done
    ok "binder_linux-dkms carregado."
}

fix_waydroid_binder_names() {
    local cfg="${WAYDROID_DIR}/waydroid.cfg"
    local nodes="${WAYDROID_DIR}/lxc/waydroid/config_nodes"

    if [[ -f "$cfg" ]]; then
        if grep -qE '^[[:space:]]*(binder|vndbinder|hwbinder)[[:space:]]*=[[:space:]]*anbox-' "$cfg"; then
            cp -a "$cfg" "${cfg}.bak.$(date +%s)"
            sed -i -E 's/^([[:space:]]*(binder|vndbinder|hwbinder)[[:space:]]*=[[:space:]]*)anbox-/\1/' "$cfg"
            log "Corrigidos nomes anbox-* em waydroid.cfg"
        fi
    fi

    if [[ -f "$nodes" ]]; then
        if grep -q 'anbox-' "$nodes"; then
            cp -a "$nodes" "${nodes}.bak.$(date +%s)"
            sed -i -E 's#/dev/anbox-(binder|vndbinder|hwbinder)#/dev/\1#g' "$nodes"
            log "Corrigidos nomes anbox-* em config_nodes"
        fi
    fi
}

stop_waydroid() {
    step "Parando sessão/container do Waydroid"
    user_systemctl stop waydroid-session.service 2>/dev/null || true
    run_as_user waydroid session stop >/dev/null 2>&1 || true
    systemctl stop waydroid-container 2>/dev/null || true
    sleep 1
    ok "Waydroid parado."
}

init_images() {
    step "Preparando imagem LineageOS GAPPS"

    local system_img="${IMAGES_DIR}/system.img"
    local vendor_img="${IMAGES_DIR}/vendor.img"
    local gapps=0
    local cfg="${WAYDROID_DIR}/waydroid.cfg"
    local answer=""

    if [[ -f "$cfg" ]] && grep -qE 'GAPPS(\.json)?' "$cfg"; then
        gapps=1
    fi

    if [[ $FORCE_IMAGES -eq 0 && -s "$system_img" && -s "$vendor_img" && $gapps -eq 1 ]]; then
        ok "Imagem GAPPS já presente; download ignorado."
        fix_waydroid_binder_names
        return 0
    fi

    if [[ $DO_IMAGES -eq 0 ]]; then
        warn "--skip-images: imagens não serão baixadas/inicializadas."
        return 0
    fi

    if [[ $ASSUME_YES -eq 0 ]]; then
        printf '\n'
        warn "Será baixada a imagem oficial LineageOS 20 GAPPS (~1,2 GB + vendor)."
        warn "Isso pode demorar dependendo da sua conexão."
        read -rp "Continuar? [s/N] " answer || true
        [[ "$answer" =~ ^[sSyY]$ ]] || die "Cancelado pelo usuário."
    fi

    local force_flag=()
    if [[ -f "$cfg" || $FORCE_IMAGES -eq 1 ]]; then
        force_flag=(-f)
    fi

    local attempt
    for attempt in 1 2; do
        log "waydroid init -s GAPPS ${force_flag[*]} (tentativa ${attempt}/2)"
        if waydroid init -s GAPPS "${force_flag[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            break
        fi
        warn "Falha na tentativa ${attempt}. Limpando cache e tentando novamente..."
        rm -f /var/tmp/waydroid-*.zip 2>/dev/null || true
        sleep 5
        [[ $attempt -eq 2 ]] && die "Falha ao baixar/inicializar as imagens. Rode novamente ou verifique $LOG_FILE."
    done

    [[ -s "$system_img" && -s "$vendor_img" ]] || die "Imagens não foram criadas em ${IMAGES_DIR}."
    fix_waydroid_binder_names
    ok "Imagem GAPPS inicializada: $(du -h "$system_img" | cut -f1) (system) + $(du -h "$vendor_img" | cut -f1) (vendor)"
}

setup_network() {
    step "Configurando rede e firewall"

    cat > /etc/sysctl.d/99-waydroid.conf <<'EOS'
# Waydroid: necessário para NAT do container
net.ipv4.ip_forward = 1
EOS
    sysctl -qw net.ipv4.ip_forward=1 || true

    install -d -m 0755 /usr/local/lib/waydroid
    cat > /usr/local/lib/waydroid/net-fix <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
log() { printf '[waydroid-net] %s\n' "$*"; }

WAN_IF="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
sysctl -qw net.ipv4.ip_forward=1 || true

for _ in $(seq 1 60); do
    if [[ -e /sys/class/net/waydroid0 ]]; then
        break
    fi
    sleep 1
done
[[ -e /sys/class/net/waydroid0 ]] || { log "waydroid0 ausente; saindo."; exit 0; }

command -v iptables >/dev/null || { log "iptables ausente; saindo."; exit 0; }

ensure() {
    local table="$1"; shift
    if ! iptables -w 5 -t "$table" -C "$@" 2>/dev/null; then
        iptables -w 5 -t "$table" -I "$@" 2>/dev/null \
            && log "regra adicionada: -t ${table} $*" \
            || log "aviso: falhou regra -t ${table} $*"
    fi
}

# DHCP/DNS vindos do container
ensure filter INPUT -i waydroid0 -p udp --dport 67 -j ACCEPT
ensure filter INPUT -i waydroid0 -p tcp --dport 67 -j ACCEPT
ensure filter INPUT -i waydroid0 -p udp --dport 53 -j ACCEPT
ensure filter INPUT -i waydroid0 -p tcp --dport 53 -j ACCEPT

# Forward do container (vence o DEFAULT_FORWARD_POLICY=DROP do ufw)
ensure filter FORWARD -i waydroid0 -j ACCEPT
ensure filter FORWARD -o waydroid0 -j ACCEPT

# NAT
if ! iptables -w 5 -t nat -C POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE 2>/dev/null; then
    iptables -w 5 -t nat -A POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE \
        && log "NAT MASQUERADE adicionado" || log "aviso: falhou NAT MASQUERADE"
fi

# MTU/VPN: clamp MSS para evitar downloads travados
if ! iptables -w 5 -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
    iptables -w 5 -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
fi

# Checksum do DHCP (evita falha de rede em alguns setups)
if ! iptables -w 5 -t mangle -C POSTROUTING -o waydroid0 -p udp --dport 68 -j CHECKSUM --checksum-fill 2>/dev/null; then
    iptables -w 5 -t mangle -A POSTROUTING -o waydroid0 -p udp --dport 68 -j CHECKSUM --checksum-fill 2>/dev/null || true
fi

# Regras persistentes do ufw (sobrevivem a reload do firewall)
if command -v ufw >/dev/null; then
    ufw_status="$(ufw status 2>/dev/null || true)"
    if [[ "$ufw_status" == *"Status: active"* ]]; then
        ufw allow in on waydroid0 comment 'Waydroid DHCP/DNS' >/dev/null 2>&1 || true
        if [[ -n "$WAN_IF" ]]; then
            ufw route allow in on waydroid0 out on "$WAN_IF" comment 'Waydroid outbound' >/dev/null 2>&1 || true
            ufw route allow in on "$WAN_IF" out on waydroid0 comment 'Waydroid return' >/dev/null 2>&1 || true
        else
            ufw route allow in on waydroid0 comment 'Waydroid outbound' >/dev/null 2>&1 || true
        fi
    fi
fi

log "rede ajustada (WAN=${WAN_IF:-desconhecida})"
EOS
    chmod 0755 /usr/local/lib/waydroid/net-fix

    cat > /etc/systemd/system/waydroid-net-fix.service <<'EOS'
[Unit]
Description=Correções de rede/firewall do Waydroid
After=waydroid-container.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/waydroid/net-fix
EOS

    cat > /etc/systemd/system/waydroid-net-fix.path <<'EOS'
[Unit]
Description=Observa waydroid0 para aplicar correções de rede

[Path]
PathExists=/sys/class/net/waydroid0
Unit=waydroid-net-fix.service

[Install]
WantedBy=multi-user.target
EOS

    systemctl daemon-reload
    systemctl enable --now waydroid-net-fix.path

    if [[ -e /sys/class/net/waydroid0 ]]; then
        /usr/local/lib/waydroid/net-fix || true
    fi

    ok "ip_forward=1, NAT e regras ufw/iptables preparados."
}

setup_user_session() {
    step "Configurando sessão do usuário"
    command -v waydroid >/dev/null || die "Waydroid não está instalado; rode o setup completo."

    install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" \
        "${TARGET_HOME}/.config/systemd/user"

    local unit="${TARGET_HOME}/.config/systemd/user/waydroid-session.service"
    if [[ -f "$unit" ]] && ! grep -q 'Waydroid Android session' "$unit"; then
        cp -a "$unit" "${unit}.bak.$(date +%s)"
    fi

    cat > "$unit" <<'EOS'
[Unit]
Description=Waydroid Android session
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/waydroid session start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOS
    chown "$TARGET_USER:$TARGET_GROUP" "$unit"

    if ! user_systemctl daemon-reload; then
        warn "Não foi possível recarregar o systemd do usuário $TARGET_USER."
    fi
    if [[ $AUTOSTART -eq 1 ]]; then
        if user_systemctl enable waydroid-session.service; then
            ok "Sessão do Waydroid habilitada no login."
        else
            warn "Falha ao habilitar a sessão no login."
        fi
    else
        ok "Serviço de sessão criado (autostart desativado)."
    fi
}

start_session() {
    [[ $GRAPHICAL -eq 1 ]] || { warn "Sem sessão gráfica; não iniciando Waydroid."; return 1; }

    step "Iniciando o Waydroid"
    systemctl start waydroid-container

    user_systemctl start waydroid-session.service 2>/dev/null || {
        warn "Falha no serviço de sessão; tentando iniciar diretamente."
        run_as_user bash -lc 'nohup waydroid session start >/tmp/waydroid-session.log 2>&1 &' || true
    }

    local status
    for _ in $(seq 1 60); do
        status="$(run_as_user waydroid status 2>/dev/null || true)"
        if grep -Eq 'Session:[[:space:]]+RUNNING' <<<"$status"; then
            ok "Sessão iniciada."
            if [[ $DO_NETWORK -eq 1 ]]; then
                if systemctl start waydroid-net-fix.service 2>/dev/null; then
                    ok "Regras de rede aplicadas."
                else
                    warn "Não foi possível aplicar as regras de rede; rode --verify."
                fi
            fi
            return 0
        fi
        sleep 1
    done

    warn "A sessão não iniciou. Veja:"
    warn "  systemctl --user status waydroid-session"
    warn "  tail -n 50 /tmp/waydroid-session.log"
    return 1
}

stop_session() {
    user_systemctl stop waydroid-session.service 2>/dev/null || true
    run_as_user waydroid session stop >/dev/null 2>&1 || true
    local _
    for _ in $(seq 1 20); do
        if [[ ! -e /sys/class/net/waydroid0 ]]; then
            break
        fi
        sleep 1
    done
}

wait_for_boot() {
    local prop _ 
    for _ in $(seq 1 180); do
        prop="$(timeout 15 waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
        if [[ "$prop" == "1" ]]; then
            return 0
        fi
        sleep 2
    done
    return 1
}

get_android_id() {
    local id="" tmp="" path
    local paths=(
        /data/data/com.google.android.gsf/databases/gservices.db
        /data/data/com.google.android.gms/databases/gservices.db
        /data/user_de/0/com.google.android.gsf/databases/gservices.db
        /data/user_de/0/com.google.android.gms/databases/gservices.db
    )

    for path in "${paths[@]}"; do
        id="$(waydroid shell -- sh -c \
            "sqlite3 '${path}' \"select value from main where name='android_id';\"" \
            2>/dev/null | tr -d '\r' | tail -n1 || true)"
        if [[ "$id" =~ ^[0-9]{6,}$ ]]; then
            printf '%s' "$id"
            return 0
        fi

        tmp="$(mktemp /tmp/gservices.XXXXXX.db)"
        if timeout 30 waydroid shell -- cat "$path" >"$tmp" 2>/dev/null; then
            # Copia o WAL também, caso a escrita recente ainda não tenha sido checkpointada.
            timeout 10 waydroid shell -- cat "${path}-wal" >"${tmp}-wal" 2>/dev/null \
                || rm -f "${tmp}-wal"
            id="$(sqlite3 "$tmp" \
                "select value from main where name='android_id';" 2>/dev/null \
                | tr -d '\r' | tail -n1 || true)"
        fi
        rm -f "$tmp" "${tmp}-wal"

        if [[ "$id" =~ ^[0-9]{6,}$ ]]; then
            printf '%s' "$id"
            return 0
        fi
    done
    return 0
}

certify_flow() {
    step "Certificação da Play Store"

    if ! grep -Eq 'Session:[[:space:]]+RUNNING' <<<"$(run_as_user waydroid status 2>/dev/null || true)"; then
        start_session || return 1
    fi

    if ! wait_for_boot; then
        warn "O Android não concluiu o boot; tente novamente com: sudo $0 --certify"
        return 1
    fi

    local pkgs
    pkgs="$(timeout 30 waydroid shell pm list packages 2>/dev/null | tr -d '\r' || true)"
    if ! grep -q 'package:com.android.vending' <<<"$pkgs"; then
        warn "Play Store (com.android.vending) não encontrada."
        warn "A imagem atual não parece ser GAPPS. Rode: sudo $0 --force-images"
        return 1
    fi
    ok "Play Store e Google Play Services presentes."

    local id
    id="$(get_android_id)"
    if [[ -z "$id" ]]; then
        warn "Android ID indisponível. Abra a Play Store uma vez e repita:"
        warn "  sudo $0 --certify"
        return 1
    fi

    printf '\n'
    printf '%sAndroid ID (GSF):%s %s\n' "$C_BOLD" "$C_RESET" "$id"
    printf 'Registre este ID em: %shttps://www.google.com/android/uncertified/%s\n' "$C_CYAN" "$C_RESET"
    printf 'Use a MESMA conta Google que será usada na Play Store.\n\n'

    if [[ $GRAPHICAL -eq 1 ]] && command -v xdg-open >/dev/null; then
        run_as_user xdg-open "https://www.google.com/android/uncertified/" >/dev/null 2>&1 &
    fi

    if [[ $ASSUME_YES -eq 0 && -t 0 ]]; then
        read -rp "Pressione ENTER depois de registrar o ID no site... " _ || true
    else
        warn "Modo não interativo: registre o ID manualmente e aguarde 10-20 minutos."
        return 0
    fi

    log "Reiniciando a sessão para aplicar a certificação..."
    waydroid shell pm clear com.android.vending >/dev/null 2>&1 || true
    stop_session
    start_session || true
    wait_for_boot || true

    run_as_user waydroid app launch com.android.vending >/dev/null 2>&1 \
        || warn "Abra a Play Store manualmente pelo menu do Waydroid."

    printf '\n'
    ok "Certificação solicitada. O Google pode levar de 10 a 20 minutos para refletir."
    printf 'Se a Play Store ainda disser "não certificado", aguarde e reinicie:\n'
    printf '  waydroid session stop && waydroid show-full-ui\n\n'
}

show_next_steps() {
    printf '\n%s================================================================%s\n' "$C_GREEN" "$C_RESET"
    printf '%s  Waydroid configurado%s\n' "$C_BOLD" "$C_RESET"
    printf '%s================================================================%s\n' "$C_GREEN" "$C_RESET"
    printf '  Iniciar UI:      waydroid show-full-ui   (ou menu do desktop)\n'
    printf '  Status:          waydroid status\n'
    printf '  Diagnóstico:     sudo %s --verify\n' "$SCRIPT_PATH"
    printf '  Certificar:      sudo %s --certify\n' "$SCRIPT_PATH"
    printf '  Sessão (user):   systemctl --user status waydroid-session\n'
    if [[ $AUTOSTART -eq 0 ]]; then
        printf '  Autostart:       sudo %s --autostart\n' "$SCRIPT_PATH"
    fi
    printf '\n  Na Play Store, faça login e baixe um app de teste.\n'
    printf '  Se um app ARM não instalar, peça o libndk (tradutor ARM).\n\n'
}

# ---------------------------------------------------------------------------
# Verificação pós-instalação (--verify)
# ---------------------------------------------------------------------------
verify_mode() {
    local failures=0

    step "Verificando binder"
    local n
    for n in binder vndbinder hwbinder; do
        if [[ -c "/dev/${n}" ]]; then
            ok "/dev/${n} presente"
        else
            err "/dev/${n} ausente"
            failures=$((failures + 1))
        fi
    done
    if [[ -f "${WAYDROID_DIR}/waydroid.cfg" ]]; then
        local b
        b="$(read_cfg binder || true)"
        [[ "$b" == "binder" ]] && ok "config usa binder padrão" \
            || warn "config usa binder='${b}'"
    fi

    step "Verificando imagens"
    if [[ -s "${IMAGES_DIR}/system.img" && -s "${IMAGES_DIR}/vendor.img" ]]; then
        ok "system.img e vendor.img presentes"
    else
        err "imagens ausentes"
        failures=$((failures + 1))
    fi
    if grep -qE 'GAPPS(\.json)?' "${WAYDROID_DIR}/waydroid.cfg" 2>/dev/null; then
        ok "imagem GAPPS configurada"
    else
        warn "system_ota não aponta para GAPPS"
    fi

    step "Verificando rede"
    /usr/local/lib/waydroid/net-fix >/dev/null 2>&1 || true
    [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]] \
        && ok "ip_forward=1" || { err "ip_forward != 1"; failures=$((failures + 1)); }

    if [[ -e /sys/class/net/waydroid0 ]]; then
        ok "waydroid0: $(ip -4 -br addr show waydroid0 | awk '{print $3}')"
        if [[ "$(ss -lun 2>/dev/null || true)" == *192.168.240.1:53* ]]; then
            ok "dnsmasq escutando em 192.168.240.1:53"
        else
            warn "dnsmasq não está escutando em 192.168.240.1:53"
        fi
        if [[ "$(iptables -w 5 -t nat -S POSTROUTING 2>/dev/null || true)" == *192.168.240.0/24* ]]; then
            ok "NAT MASQUERADE presente"
        else
            err "NAT MASQUERADE ausente"
            failures=$((failures + 1))
        fi
        if [[ "$(iptables -w 5 -S FORWARD 2>/dev/null || true)" == *waydroid0* ]]; then
            ok "regras de FORWARD presentes"
        else
            err "regras de FORWARD ausentes"
            failures=$((failures + 1))
        fi
    else
        warn "waydroid0 ausente (sessão parada)."
    fi

    step "Verificando sessão e Play Store"
    local status
    status="$(run_as_user waydroid status 2>/dev/null || true)"
    printf '%s\n' "$status" | sed 's/^/  /'
    if grep -Eq 'Session:[[:space:]]+RUNNING' <<<"$status"; then
        if wait_for_boot; then
            ok "Android boot concluído"
            local pkgs
            pkgs="$(timeout 30 waydroid shell pm list packages 2>/dev/null | tr -d '\r' || true)"
            grep -q 'package:com.android.vending' <<<"$pkgs" \
                && ok "Play Store presente" || { err "Play Store ausente"; failures=$((failures + 1)); }
            grep -q 'package:com.google.android.gms' <<<"$pkgs" \
                && ok "Google Play Services presente" || { err "GMS ausente"; failures=$((failures + 1)); }

            step "Teste de internet dentro do Android"
            local net_ok=0 attempt
            for attempt in $(seq 1 15); do
                if timeout 10 waydroid shell -- ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
                    net_ok=1
                    break
                fi
                sleep 2
            done
            if [[ $net_ok -eq 1 ]]; then
                ok "ping 1.1.1.1 OK"
            else
                err "sem ping para 1.1.1.1"
                failures=$((failures + 1))
            fi

            local dns_ok=0
            for attempt in $(seq 1 10); do
                if timeout 10 waydroid shell -- ping -c 1 -W 3 google.com >/dev/null 2>&1; then
                    dns_ok=1
                    break
                fi
                sleep 2
            done
            if [[ $dns_ok -eq 1 ]]; then
                ok "DNS/rota para google.com OK"
            else
                err "falha de DNS/rota para google.com"
                failures=$((failures + 1))
            fi

            local id
            id="$(get_android_id)"
            if [[ -n "$id" ]]; then
                printf '\n  Android ID para certificação: %s\n' "$id"
            fi
        else
            warn "Android ainda não concluiu o boot."
        fi
    else
        warn "Sessão parada; rede interna não testada."
    fi

    printf '\n'
    if [[ $failures -eq 0 ]]; then
        ok "Verificação concluída sem falhas críticas."
        return 0
    fi
    err "Verificação concluída com ${failures} falha(s)."
    return 1
}

# ---------------------------------------------------------------------------
# Fluxo principal
# ---------------------------------------------------------------------------
case "$MODE" in
    check)
        check_mode
        ;;
    verify)
        verify_mode
        ;;
    certify)
        certify_flow
        ;;
    autostart)
        setup_user_session
        ;;
    setup)
        mkdir -p "$STATE_DIR"
        preflight
        install_packages
        setup_binderfs
        stop_waydroid
        init_images
        systemctl enable --now waydroid-container
        if [[ $DO_NETWORK -eq 1 ]]; then
            setup_network
        fi
        fix_waydroid_binder_names
        setup_user_session

        if [[ $DO_START -eq 1 ]]; then
            if start_session; then
                if wait_for_boot; then
                    ok "Android iniciado com sucesso."
                    if [[ $DO_CERTIFY -eq 1 ]]; then
                        certify_flow || true
                    fi
                else
                    warn "Boot do Android demorou mais que o esperado; verifique com --verify."
                fi
            fi
        fi

        show_next_steps
        ;;
esac
