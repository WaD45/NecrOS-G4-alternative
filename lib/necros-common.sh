#!/bin/sh
# ============================================================================
#  NecrOS Common Library
#  Shared functions for all NecrOS scripts — source this, don't execute it.
# ============================================================================

# Guard against double-sourcing
[ -n "$_NECROS_LIB_LOADED" ] && return 0
_NECROS_LIB_LOADED=1

# ---------------------------------------------------------------------------
# Version (read from VERSION file if available, else fallback)
# ---------------------------------------------------------------------------
if [ -f /usr/local/necros/VERSION ]; then
    NECROS_VERSION=$(tr -d '[:space:]' < /usr/local/necros/VERSION)
elif [ -f "$(dirname "$0")/../VERSION" ]; then
    NECROS_VERSION=$(tr -d '[:space:]' < "$(dirname "$0")/../VERSION")
else
    NECROS_VERSION="1.0.0"
fi
export NECROS_VERSION

# ---------------------------------------------------------------------------
# Terminal colours (POSIX-safe, degrades gracefully without tty)
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi
export RED GREEN YELLOW BLUE MAGENTA CYAN BOLD NC

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
NECROS_LOG="/var/log/necros.log"

_log_write() {
    local _lvl="$1"; shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_lvl" "$*" \
        >> "$NECROS_LOG" 2>/dev/null || true
}

log()   { _log_write "INFO"  "$@"; printf '%s[+]%s %s\n' "$GREEN"  "$NC" "$*"; }
warn()  { _log_write "WARN"  "$@"; printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*"; }
err()   { _log_write "ERROR" "$@"; printf '%s[✗]%s %s\n' "$RED"    "$NC" "$*"; }
die()   { err "$@"; exit 1; }
info()  { printf '%s[*]%s %s\n' "$CYAN" "$NC" "$*"; }
ok()    { printf '%s[✓]%s %s\n' "$GREEN" "$NC" "$*"; }

# ---------------------------------------------------------------------------
# Architecture detection
# ---------------------------------------------------------------------------
detect_arch() {
    NECROS_ARCH=$(uname -m)
    case "$NECROS_ARCH" in
        i686|i386|i486|i586)
            NECROS_ARCH_FAMILY="x86"
            NECROS_BITS=32
            ;;
        x86_64|amd64)
            NECROS_ARCH_FAMILY="x86_64"
            NECROS_BITS=64
            ;;
        aarch64|arm64)
            NECROS_ARCH_FAMILY="aarch64"
            NECROS_BITS=64
            ;;
        armv7l|armv6l)
            NECROS_ARCH_FAMILY="arm"
            NECROS_BITS=32
            ;;
        ppc|powerpc)
            NECROS_ARCH_FAMILY="ppc"
            NECROS_BITS=32
            ;;
        ppc64|ppc64le)
            NECROS_ARCH_FAMILY="ppc64"
            NECROS_BITS=64
            ;;
        *)
            NECROS_ARCH_FAMILY="unknown"
            NECROS_BITS=0
            ;;
    esac
    export NECROS_ARCH NECROS_ARCH_FAMILY NECROS_BITS
}

# ---------------------------------------------------------------------------
# Distribution detection
# ---------------------------------------------------------------------------
detect_distro() {
    if [ -f /etc/alpine-release ]; then
        NECROS_DISTRO="alpine"
    elif [ -f /etc/adelie-release ]; then
        NECROS_DISTRO="adelie"
    else
        NECROS_DISTRO="unknown"
    fi
    export NECROS_DISTRO
}

# Convenience checks
is_32bit() { [ "$NECROS_BITS" -eq 32 ] 2>/dev/null; }
is_ppc()   { [ "$NECROS_ARCH_FAMILY" = "ppc" ] || [ "$NECROS_ARCH_FAMILY" = "ppc64" ]; }
is_big_endian() {
    [ "$NECROS_ARCH" = "ppc64le" ] && return 1
    is_ppc && return 0
    return 1
}
is_lowmem() { [ "$(get_mem_mb)" -lt 512 ] 2>/dev/null; }

# ---------------------------------------------------------------------------
# System probes
# ---------------------------------------------------------------------------
get_mem_mb() {
    awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo 2>/dev/null || echo 0
}

get_disk_free_mb() {
    df -m "${1:-/}" 2>/dev/null | awk 'NR==2 { print $4 }'
}

get_alpine_version() {
    if [ -f /etc/alpine-release ]; then
        cut -d. -f1,2 /etc/alpine-release
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Requirement checks
# ---------------------------------------------------------------------------
require_root() {
    [ "$(id -u)" -eq 0 ] || die "Ce script doit être exécuté en tant que root."
}

require_compatible_base() {
    [ -z "$NECROS_DISTRO" ] && detect_distro
    if [ "$NECROS_DISTRO" = "alpine" ] || [ "$NECROS_DISTRO" = "adelie" ]; then
        return 0
    fi
    die "NecrOS nécessite Alpine Linux ou Adélie Linux comme base."
}

require_alpine() {
    require_compatible_base
}

require_mem() {
    local _min="${1:-256}"
    local _actual
    _actual=$(get_mem_mb)
    [ "$_actual" -ge "$_min" ] 2>/dev/null || \
        die "RAM insuffisante: ${_actual}MB (minimum ${_min}MB)"
}

require_disk() {
    local _min="${1:-500}" _mount="${2:-/}"
    local _actual
    _actual=$(get_disk_free_mb "$_mount")
    [ "$_actual" -ge "$_min" ] 2>/dev/null || \
        die "Espace disque insuffisant: ${_actual}MB libre sur $_mount (minimum ${_min}MB)"
}

# ---------------------------------------------------------------------------
# Package helpers (wrapping apk)
# ---------------------------------------------------------------------------
pkg_install() {
    # Install packages, tolerating individual failures.
    # Usage: pkg_install pkg1 pkg2 pkg3 ...
    local _failed="" _pkg
    for _pkg in "$@"; do
        if ! apk info -e "$_pkg" >/dev/null 2>&1; then
            apk add --no-cache "$_pkg" >> "$NECROS_LOG" 2>&1 || {
                warn "Paquet indisponible: $_pkg"
                _failed="$_failed $_pkg"
            }
        fi
    done
    [ -z "$_failed" ] || warn "Paquets manquants:$_failed"
}

pkg_installed() {
    apk info -e "$1" >/dev/null 2>&1
}

pip_install() {
    pip3 install --break-system-packages --quiet "$@" >> "$NECROS_LOG" 2>&1 || \
        warn "pip install échoué pour: $*"
}

# ---------------------------------------------------------------------------
# Swap management (crucial for 256MB machines)
# ---------------------------------------------------------------------------
ensure_swap() {
    local _size_mb="${1:-256}"
    local _swapfile="/var/cache/necros.swap"
    if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -gt 0 ]; then
        return 0  # Swap already active
    fi
    if [ ! -f "$_swapfile" ]; then
        info "Création d'un swap de ${_size_mb}MB..."
        dd if=/dev/zero of="$_swapfile" bs=1M count="$_size_mb" status=none 2>/dev/null
        chmod 600 "$_swapfile"
        mkswap "$_swapfile" >> "$NECROS_LOG" 2>&1
    fi
    swapon "$_swapfile" 2>/dev/null && log "Swap activé (${_size_mb}MB)" || \
        warn "Impossible d'activer le swap"
}

# ---------------------------------------------------------------------------
# Cleanup trap helper
# ---------------------------------------------------------------------------
_necros_cleanup_hooks=""

necros_on_exit() {
    _necros_cleanup_hooks="$_necros_cleanup_hooks
$1"
}

_necros_run_cleanup() {
    local _line
    echo "$_necros_cleanup_hooks" | while IFS= read -r _line; do
        [ -n "$_line" ] && eval "$_line" 2>/dev/null || true
    done
}

trap _necros_run_cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Idempotent marker system
# ---------------------------------------------------------------------------
NECROS_MARKERS="/var/lib/necros/markers"

mark_done() {
    mkdir -p "$NECROS_MARKERS"
    touch "$NECROS_MARKERS/$1"
}

is_done() {
    [ -f "$NECROS_MARKERS/$1" ]
}

run_once() {
    # Usage: run_once "step_name" command args...
    local _step="$1"; shift
    if is_done "$_step"; then
        info "Étape déjà complétée: $_step (skip)"
        return 0
    fi
    "$@"
    mark_done "$_step"
}

# ---------------------------------------------------------------------------
# NecrOS banner
# ---------------------------------------------------------------------------
necros_banner() {
    printf '%s' "$CYAN"
    cat << 'BANNER'

    ███╗   ██╗███████╗ ██████╗██████╗  ██████╗ ███████╗
    ████╗  ██║██╔════╝██╔════╝██╔══██╗██╔═══██╗██╔════╝
    ██╔██╗ ██║█████╗  ██║     ██████╔╝██║   ██║███████╗
    ██║╚██╗██║██╔══╝  ██║     ██╔══██╗██║   ██║╚════██║
    ██║ ╚████║███████╗╚██████╗██║  ██║╚██████╔╝███████║
    ╚═╝  ╚═══╝╚══════╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
BANNER
    printf '%s\n' "$NC"
    printf '    %s"Resurrecting the Silicon Dead"%s  —  v%s\n\n' \
        "$YELLOW" "$NC" "$NECROS_VERSION"
}

# Auto-detect architecture and distro on source
detect_arch
detect_distro
