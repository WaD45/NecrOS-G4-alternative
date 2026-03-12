#!/bin/sh
# ============================================================================
#  NecrOS UPDATE v1.0 — Self-updater
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
# shellcheck source=../lib/necros-common.sh
. "$_LIB" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
    log()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
    warn() { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
    err()  { printf "${RED}[✗]${NC} %s\n" "$1"; }
    die()  { err "$@"; exit 1; }
    ok()   { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
}

REPO_URL="https://github.com/WaD45/NecrOS"
NECROS_DIR="/usr/local/necros"
TMP_DIR="/tmp/necros-update-$$"

show_help() {
    cat <<EOF
NecrOS UPDATE v1.0

Usage: necros-update [COMMAND]

Commands:
  check      Check for updates (default)
  pull       Download and apply updates
  system     Update Alpine packages
  all        Update everything (NecrOS + Alpine)
  -h,--help  Show help
EOF
}

check_update() {
    log "Vérification des mises à jour..."

    local _current
    _current=$(cat "$NECROS_DIR/VERSION" 2>/dev/null || echo "0.0.0")
    info "Version actuelle: $_current"

    local _remote
    _remote=$(curl -sL "${REPO_URL}/raw/main/VERSION" 2>/dev/null | head -1)

    if [ -z "$_remote" ]; then
        warn "Impossible de vérifier la version distante"
        return 1
    fi

    info "Version distante: $_remote"

    if [ "$_current" = "$_remote" ]; then
        ok "NecrOS est à jour (v${_current})"
        return 0
    else
        warn "Mise à jour disponible: v${_current} → v${_remote}"
        return 2
    fi
}

pull_update() {
    require_root

    log "Téléchargement de la mise à jour..."

    mkdir -p "$TMP_DIR"
    necros_on_exit "rm -rf '$TMP_DIR'"

    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 "$REPO_URL.git" "$TMP_DIR/repo" >> "$NECROS_LOG" 2>&1 || \
            die "Échec du clone git"
    else
        wget -q "${REPO_URL}/archive/refs/heads/main.tar.gz" -O "$TMP_DIR/necros.tar.gz" || \
            die "Échec du téléchargement"
        tar xzf "$TMP_DIR/necros.tar.gz" -C "$TMP_DIR" || die "Échec de l'extraction"
        mv "$TMP_DIR"/NecrOS-* "$TMP_DIR/repo"
    fi

    log "Application de la mise à jour..."

    # Backup current
    cp -a "$NECROS_DIR" "${NECROS_DIR}.bak-$(date +%Y%m%d)" 2>/dev/null || true

    # Update files
    cp "$TMP_DIR/repo/VERSION" "$NECROS_DIR/"
    cp "$TMP_DIR/repo/lib/necros-common.sh" "$NECROS_DIR/lib/"

    for _f in "$TMP_DIR/repo/core/"*.sh; do
        [ -f "$_f" ] && cp "$_f" "$NECROS_DIR/core/"
    done
    for _f in "$TMP_DIR/repo/toolbox/"*.sh; do
        [ -f "$_f" ] && cp "$_f" "$NECROS_DIR/toolbox/"
    done

    # Fix permissions
    chmod +x "$NECROS_DIR"/core/*.sh "$NECROS_DIR"/toolbox/*.sh 2>/dev/null

    rm -rf "$TMP_DIR"

    ok "Mise à jour appliquée (v$(cat "$NECROS_DIR/VERSION"))"
}

update_system() {
    require_root
    log "Mise à jour des paquets Alpine..."
    apk update >> "$NECROS_LOG" 2>&1
    apk upgrade >> "$NECROS_LOG" 2>&1
    ok "Paquets système mis à jour"
}

# CLI
case "${1:---check}" in
    check|--check) check_update ;;
    pull)          pull_update ;;
    system)        update_system ;;
    all)           pull_update; update_system ;;
    -h|--help)     show_help ;;
    *)             show_help; exit 1 ;;
esac
