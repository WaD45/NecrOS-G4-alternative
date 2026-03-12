#!/bin/sh
# ============================================================================
#  NecrOS RECON v1.0 — Automated Reconnaissance Pipeline
#  Quick target profiling from a single command.
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

# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
NecrOS RECON v1.0 — Automated Reconnaissance

Usage: necros-recon <target> [OPTIONS]

Target: IP address, CIDR range, or domain name

Options:
  -o, --output DIR   Save results to directory (default: ./recon_<target>)
  -q, --quick        Quick scan (top 100 ports, no scripts)
  -f, --full         Full scan (all ports, all scripts, OS detection)
  -w, --web          Web-focused recon (HTTP discovery + headers)
  -p, --passive      Passive only (no active scanning)
  --no-dns           Skip DNS enumeration
  -h, --help         Show help

Examples:
  necros-recon 192.168.1.0/24              # Standard recon on subnet
  necros-recon target.com -f -o results    # Full scan, save to results/
  necros-recon target.com -w               # Web-focused recon
  necros-recon target.com -p               # Passive only (OSINT)
EOF
}

# ---------------------------------------------------------------------------
# Verify required tools
# ---------------------------------------------------------------------------
check_tools() {
    local _missing=""
    for _tool in nmap curl dig; do
        command -v "$_tool" >/dev/null 2>&1 || _missing="$_missing $_tool"
    done
    [ -z "$_missing" ] && return 0
    die "Outils manquants:$_missing — Lancez necros-toolbox pour les installer"
}

# ---------------------------------------------------------------------------
# Recon modules
# ---------------------------------------------------------------------------
recon_dns() {
    local _target="$1" _out="$2"
    info "DNS enumeration: $_target"

    {
        echo "=== DNS Records ==="
        dig ANY "$_target" +noall +answer 2>/dev/null || echo "(dig failed)"
        echo ""
        echo "=== Nameservers ==="
        dig NS "$_target" +short 2>/dev/null
        echo ""
        echo "=== MX Records ==="
        dig MX "$_target" +short 2>/dev/null
        echo ""
        echo "=== TXT Records ==="
        dig TXT "$_target" +short 2>/dev/null
        echo ""
        echo "=== Reverse DNS ==="
        # Only if target is an IP
        echo "$_target" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' && \
            dig -x "$_target" +short 2>/dev/null
    } > "$_out/dns.txt" 2>&1

    ok "DNS → $_out/dns.txt"
}

recon_whois() {
    local _target="$1" _out="$2"
    if ! command -v whois >/dev/null 2>&1; then
        warn "whois non disponible, skip"
        return
    fi
    info "WHOIS: $_target"
    whois "$_target" > "$_out/whois.txt" 2>&1 || true
    ok "WHOIS → $_out/whois.txt"
}

recon_portscan_quick() {
    local _target="$1" _out="$2"
    info "Quick port scan (top 100): $_target"
    nmap -T4 -F --open -oN "$_out/nmap_quick.txt" -oX "$_out/nmap_quick.xml" \
        "$_target" 2>/dev/null || warn "nmap quick scan failed"
    ok "Quick scan → $_out/nmap_quick.txt"
}

recon_portscan_standard() {
    local _target="$1" _out="$2"
    info "Standard port scan (top 1000 + scripts): $_target"
    nmap -sV -sC -T4 --open -oN "$_out/nmap_standard.txt" -oX "$_out/nmap_standard.xml" \
        "$_target" 2>/dev/null || warn "nmap standard scan failed"
    ok "Standard scan → $_out/nmap_standard.txt"
}

recon_portscan_full() {
    local _target="$1" _out="$2"
    info "Full port scan (all 65535 ports): $_target"
    warn "Ceci peut prendre plusieurs minutes..."
    nmap -p- -sV -sC -O -T4 --open -oN "$_out/nmap_full.txt" -oX "$_out/nmap_full.xml" \
        "$_target" 2>/dev/null || warn "nmap full scan failed"
    ok "Full scan → $_out/nmap_full.txt"
}

recon_web() {
    local _target="$1" _out="$2"
    info "Web reconnaissance: $_target"

    # HTTP headers
    for _proto in http https; do
        local _url="${_proto}://${_target}"
        info "Headers: $_url"
        curl -sI -m 10 "$_url" > "$_out/headers_${_proto}.txt" 2>/dev/null || true
    done

    # Technology fingerprint
    if command -v whatweb >/dev/null 2>&1; then
        info "Technology fingerprinting..."
        whatweb --color=never "$_target" > "$_out/whatweb.txt" 2>/dev/null || true
    fi

    # SSL/TLS check
    if command -v openssl >/dev/null 2>&1; then
        info "SSL/TLS check..."
        echo | openssl s_client -connect "$_target:443" -servername "$_target" \
            2>/dev/null | openssl x509 -noout -text 2>/dev/null > "$_out/ssl.txt" || true
    fi

    # robots.txt
    curl -s -m 5 "https://${_target}/robots.txt" > "$_out/robots.txt" 2>/dev/null || \
        curl -s -m 5 "http://${_target}/robots.txt" > "$_out/robots.txt" 2>/dev/null || true

    ok "Web recon → $_out/"
}

recon_passive() {
    local _target="$1" _out="$2"
    info "Passive OSINT: $_target"

    # crt.sh — certificate transparency
    info "Certificate Transparency (crt.sh)..."
    curl -s "https://crt.sh/?q=%25.${_target}&output=json" 2>/dev/null | \
        jq -r '.[].name_value' 2>/dev/null | sort -u > "$_out/subdomains_crt.txt" || true

    # Basic Google dorks (just build the list, don't execute)
    {
        echo "=== Google Dorks pour ${_target} ==="
        echo "site:${_target}"
        echo "site:${_target} filetype:pdf"
        echo "site:${_target} filetype:doc OR filetype:docx"
        echo "site:${_target} filetype:xls OR filetype:xlsx"
        echo "site:${_target} inurl:admin"
        echo "site:${_target} inurl:login"
        echo "site:${_target} intitle:\"index of\""
        echo "site:${_target} ext:sql OR ext:db OR ext:log"
        echo "site:${_target} inurl:wp-content"
    } > "$_out/google_dorks.txt"

    ok "Passive OSINT → $_out/"
}

generate_report() {
    local _out="$1" _target="$2"
    info "Génération du rapport..."

    cat > "$_out/REPORT.md" <<REPORT
# NecrOS Recon Report
**Target:** ${_target}
**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Operator:** $(whoami)@$(hostname)

## Files generated
$(ls -1 "$_out/" | grep -v REPORT.md | sed 's/^/- /')

## Quick Summary
$(if [ -f "$_out/nmap_quick.txt" ]; then
    echo '### Open Ports'
    grep "^[0-9]" "$_out/nmap_quick.txt" 2>/dev/null | head -20
elif [ -f "$_out/nmap_standard.txt" ]; then
    echo '### Open Ports'
    grep "^[0-9]" "$_out/nmap_standard.txt" 2>/dev/null | head -20
fi)

$(if [ -f "$_out/subdomains_crt.txt" ] && [ -s "$_out/subdomains_crt.txt" ]; then
    echo "### Subdomains found (crt.sh)"
    echo "\`\`\`"
    head -20 "$_out/subdomains_crt.txt"
    echo "\`\`\`"
fi)

---
*Generated by NecrOS RECON v1.0*
REPORT

    ok "Rapport → $_out/REPORT.md"
}

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
TARGET=""
OUTPUT=""
SCAN_MODE="standard"  # quick | standard | full | web | passive
SKIP_DNS=0

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output) OUTPUT="$2"; shift ;;
        -q|--quick)  SCAN_MODE="quick" ;;
        -f|--full)   SCAN_MODE="full" ;;
        -w|--web)    SCAN_MODE="web" ;;
        -p|--passive) SCAN_MODE="passive" ;;
        --no-dns)    SKIP_DNS=1 ;;
        -h|--help)   show_help; exit 0 ;;
        -*)          warn "Option inconnue: $1" ;;
        *)           [ -z "$TARGET" ] && TARGET="$1" ;;
    esac
    shift
done

[ -z "$TARGET" ] && { show_help; exit 1; }

# Sanitize target for directory name
_safe_target=$(echo "$TARGET" | sed 's|[/:]|_|g')
OUTPUT="${OUTPUT:-./recon_${_safe_target}}"
mkdir -p "$OUTPUT"

check_tools

printf '\n%s' "$CYAN"
cat <<'BANNER'
    ╦═╗╔═╗╔═╗╔═╗╔╗╔
    ╠╦╝║╣ ║  ║ ║║║║
    ╩╚═╚═╝╚═╝╚═╝╝╚╝
BANNER
printf '%s\n' "$NC"
log "Cible: $TARGET"
log "Mode: $SCAN_MODE"
log "Sortie: $OUTPUT"
echo ""

# Execute recon pipeline
case "$SCAN_MODE" in
    passive)
        [ "$SKIP_DNS" -eq 0 ] && recon_dns "$TARGET" "$OUTPUT"
        recon_whois "$TARGET" "$OUTPUT"
        recon_passive "$TARGET" "$OUTPUT"
        ;;
    quick)
        [ "$SKIP_DNS" -eq 0 ] && recon_dns "$TARGET" "$OUTPUT"
        recon_portscan_quick "$TARGET" "$OUTPUT"
        ;;
    standard)
        [ "$SKIP_DNS" -eq 0 ] && recon_dns "$TARGET" "$OUTPUT"
        recon_whois "$TARGET" "$OUTPUT"
        recon_portscan_standard "$TARGET" "$OUTPUT"
        recon_passive "$TARGET" "$OUTPUT"
        ;;
    full)
        [ "$SKIP_DNS" -eq 0 ] && recon_dns "$TARGET" "$OUTPUT"
        recon_whois "$TARGET" "$OUTPUT"
        recon_portscan_full "$TARGET" "$OUTPUT"
        recon_web "$TARGET" "$OUTPUT"
        recon_passive "$TARGET" "$OUTPUT"
        ;;
    web)
        [ "$SKIP_DNS" -eq 0 ] && recon_dns "$TARGET" "$OUTPUT"
        recon_portscan_quick "$TARGET" "$OUTPUT"
        recon_web "$TARGET" "$OUTPUT"
        recon_passive "$TARGET" "$OUTPUT"
        ;;
esac

generate_report "$OUTPUT" "$TARGET"

echo ""
ok "Reconnaissance terminée. Résultats dans: $OUTPUT/"
echo ""
