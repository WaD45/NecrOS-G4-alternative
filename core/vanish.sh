#!/bin/sh
# ============================================================================
#  NecrOS VANISH v2.0 — "Leave No Trace"
#  Anti-forensics & emergency wipe — Use responsibly.
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
    info() { printf "${CYAN}[*]${NC} %s\n" "$1"; }
    ok()   { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
}

require_root

# ---------------------------------------------------------------------------
banner_vanish() {
    printf '%s' "$RED"
    cat << 'EOF'

    ██╗   ██╗ █████╗ ███╗   ██╗██╗███████╗██╗  ██╗
    ██║   ██║██╔══██╗████╗  ██║██║██╔════╝██║  ██║
    ██║   ██║███████║██╔██╗ ██║██║███████╗███████║
    ╚██╗ ██╔╝██╔══██║██║╚██╗██║██║╚════██║██╔══██║
     ╚████╔╝ ██║  ██║██║ ╚████║██║███████║██║  ██║
      ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚═╝  ╚═╝
EOF
    printf '%s\n' "$NC"
    printf '    %s"Dans l'\''ombre, nous disparaissons"%s\n\n' "$CYAN" "$NC"
}

# ---------------------------------------------------------------------------
# Individual wipe functions
# ---------------------------------------------------------------------------
clear_logs() {
    info "Effacement des logs système..."
    local _f
    for _f in \
        /var/log/messages /var/log/syslog /var/log/auth.log \
        /var/log/secure /var/log/kern.log /var/log/daemon.log \
        /var/log/wtmp /var/log/btmp /var/log/lastlog \
        /var/log/faillog /var/log/dmesg; do
        [ -f "$_f" ] && : > "$_f" 2>/dev/null
    done
    # OpenRC logs
    find /var/log -name "*.log" -type f -exec sh -c ': > "$1"' _ {} \; 2>/dev/null
    # journalctl if present
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --rotate 2>/dev/null
        journalctl --vacuum-time=1s 2>/dev/null
    fi
    ok "Logs système effacés"
}

clear_history() {
    info "Effacement des historiques shell..."
    find /root /home -maxdepth 3 \( \
        -name ".*_history" -o -name ".lesshst" -o -name ".viminfo" \
        -o -name ".python_history" -o -name ".mysql_history" \
        -o -name ".psql_history" -o -name ".sqlite_history" \
        -o -name ".wget-hsts" -o -name ".recently-used.xbel" \
    \) -type f -delete 2>/dev/null
    # Kill current shell history
    unset HISTFILE
    export HISTSIZE=0 HISTFILESIZE=0 SAVEHIST=0
    ok "Historiques shell effacés"
}

clear_connections() {
    info "Effacement des traces de connexion..."
    find /root /home -maxdepth 3 -name "known_hosts" -type f -delete 2>/dev/null
    find /root /home -maxdepth 3 -name "authorized_keys" -type f 2>/dev/null | \
        while read -r _f; do warn "authorized_keys trouvé: $_f (non supprimé)"; done
    : > /var/log/lastlog 2>/dev/null
    : > /var/log/wtmp 2>/dev/null
    : > /var/run/utmp 2>/dev/null
    ok "Traces de connexion effacées"
}

clear_cache() {
    info "Effacement du cache et fichiers temporaires..."
    # Drop kernel caches
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    # Temp files
    rm -rf /tmp/* /var/tmp/* 2>/dev/null
    # APK cache
    apk cache clean 2>/dev/null
    # User caches
    find /root /home -maxdepth 2 -name ".cache" -type d -exec rm -rf {} + 2>/dev/null
    # Thumbnail caches
    find /root /home -maxdepth 3 -name "thumbnails" -type d -exec rm -rf {} + 2>/dev/null
    ok "Cache et temporaires effacés"
}

clear_network_traces() {
    info "Effacement des traces réseau..."
    # ARP cache
    ip neigh flush all 2>/dev/null || arp -d -a 2>/dev/null || true
    # Conntrack
    command -v conntrack >/dev/null 2>&1 && conntrack -F 2>/dev/null || true
    # DNS cache (if dnsmasq)
    command -v killall >/dev/null 2>&1 && killall -HUP dnsmasq 2>/dev/null || true
    # Flush routing cache
    ip route flush cache 2>/dev/null || true
    ok "Traces réseau effacées"
}

clear_necros_traces() {
    info "Effacement des traces NecrOS..."
    : > /var/log/necros.log 2>/dev/null
    rm -rf /var/lib/necros/markers 2>/dev/null
    ok "Traces NecrOS effacées"
}

secure_wipe_free_space() {
    info "Écrasement de l'espace libre (peut prendre du temps)..."
    local _wipe="/tmp/.necros_wipe_$$"
    dd if=/dev/urandom of="$_wipe" bs=1M count=50 2>/dev/null || true
    sync
    rm -f "$_wipe"
    # Overwrite with zeros
    dd if=/dev/zero of="$_wipe" bs=1M count=50 2>/dev/null || true
    sync
    rm -f "$_wipe"
    ok "Espace libre écrasé"
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
mode_ghost() {
    printf '%s[GHOST MODE]%s\n' "$CYAN" "$NC"
    clear_logs
    clear_history
    ok "Mode fantôme activé"
}

mode_stealth() {
    printf '%s[STEALTH MODE]%s\n' "$CYAN" "$NC"
    clear_logs
    clear_history
    clear_connections
    clear_cache
    clear_network_traces
    ok "Mode furtif activé"
}

mode_nuclear() {
    printf '%s' "$RED"
    cat << 'NUKE'
    ╔══════════════════════════════════════════════════════╗
    ║   ⚠  NUCLEAR MODE — DESTRUCTION TOTALE  ⚠          ║
    ║                                                      ║
    ║   Ceci va effacer :                                  ║
    ║   • Tous les logs système                            ║
    ║   • Tous les historiques shell                       ║
    ║   • Toutes les traces réseau                         ║
    ║   • Tout le cache et les temporaires                 ║
    ║   • Écraser l'espace libre du disque                 ║
    ║                                                      ║
    ║   CETTE ACTION EST IRRÉVERSIBLE.                     ║
    ╚══════════════════════════════════════════════════════╝
NUKE
    printf '%s\n' "$NC"

    if [ "$FORCE" != "1" ]; then
        printf '%sTapez VANISH pour confirmer: %s' "$YELLOW" "$NC"
        read -r _confirm
        [ "$_confirm" = "VANISH" ] || { err "Annulé."; exit 1; }
    fi

    printf '%s[NUCLEAR]%s Initialisation de la destruction...\n' "$RED" "$NC"
    clear_logs
    clear_history
    clear_connections
    clear_cache
    clear_network_traces
    clear_necros_traces
    secure_wipe_free_space

    printf '%s[NUCLEAR]%s Protocole terminé. Aucune trace ne subsiste.\n' "$RED" "$NC"
}

mode_status() {
    printf '%s[STATUS]%s Analyse des éléments effaçables:\n\n' "$CYAN" "$NC"

    printf '  Logs:\n'
    local _log_size
    _log_size=$(find /var/log -type f -name "*.log" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
    printf '    Taille totale: %s\n' "${_log_size:-0}"

    printf '  Historiques:\n'
    find /root /home -maxdepth 3 -name ".*_history" -type f 2>/dev/null | while read -r _f; do
        printf '    %s (%s)\n' "$_f" "$(wc -l < "$_f" 2>/dev/null || echo '?') lignes"
    done

    printf '  Cache:\n'
    printf '    /tmp: %s\n' "$(du -sh /tmp 2>/dev/null | cut -f1)"
    printf '    /var/tmp: %s\n' "$(du -sh /var/tmp 2>/dev/null | cut -f1)"

    printf '  Réseau:\n'
    printf '    ARP entries: %s\n' "$(ip neigh show 2>/dev/null | wc -l)"
    echo ""
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
NecrOS VANISH v2.0 — Anti-Forensics Toolkit

Usage: necros-vanish [MODE] [OPTIONS]

Modes:
  ghost      Efface logs et historiques (défaut)
  stealth    Ghost + connexions + cache + réseau
  nuclear    Destruction totale + wipe espace libre (DANGER)
  status     Affiche les éléments effaçables

Options:
  -y, --yes    Pas de confirmation (mode nuclear)
  -q, --quiet  Mode silencieux
  -h, --help   Aide

Exemples:
  necros-vanish                  # Mode ghost
  necros-vanish stealth          # Mode furtif
  necros-vanish nuclear -y       # Destruction sans confirmation
EOF
}

MODE="ghost"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        ghost|stealth|nuclear|status) MODE="$1" ;;
        -y|--yes) FORCE=1 ;;
        -q|--quiet) exec >/dev/null ;;
        -h|--help) show_help; exit 0 ;;
        *) warn "Option inconnue: $1" ;;
    esac
    shift
done

banner_vanish

case "$MODE" in
    ghost)   mode_ghost ;;
    stealth) mode_stealth ;;
    nuclear) mode_nuclear ;;
    status)  mode_status ;;
esac
