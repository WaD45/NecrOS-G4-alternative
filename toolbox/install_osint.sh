#!/bin/sh
# ============================================================================
#  NecrOS Toolbox — OSINT & Reconnaissance
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
. "$_LIB" 2>/dev/null || { echo "[!] Library not found"; exit 1; }

require_root
detect_arch

necros_banner
log "Installation de la Toolbox OSINT..."

# --- DNS tools ---
log "Outils DNS avancés..."
pkg_install bind-tools whois ldns-tools

# --- Web scraping ---
log "Outils de scraping..."
pip_install requests beautifulsoup4 lxml

# --- Email OSINT ---
log "Outils email..."
pip_install holehe 2>/dev/null || info "holehe non disponible"

# --- Subdomain enumeration ---
log "Énumération de sous-domaines..."
# Amass is too heavy for 32-bit, use lighter alternatives
if ! is_32bit && ! is_lowmem; then
    # Try to get subfinder
    if command -v go >/dev/null 2>&1; then
        go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>/dev/null && \
            cp "$(go env GOPATH)/bin/subfinder" /usr/local/bin/ 2>/dev/null || true
    fi
fi

# --- Network OSINT ---
log "OSINT réseau..."
pkg_install traceroute mtr whois

# --- Metadata extraction ---
log "Extraction de métadonnées..."
pkg_install exiftool

# --- Shodan CLI (Python-based, lightweight) ---
pip_install shodan

# --- theHarvester ---
pip_install theharvester 2>/dev/null || info "theHarvester non disponible via pip"

# --- Helper scripts ---
cat > /usr/local/bin/necros-osint << 'SCRIPT'
#!/bin/sh
# NecrOS — Quick OSINT on a domain
TARGET="$1"
[ -z "$TARGET" ] && { echo "Usage: necros-osint <domain>"; exit 1; }

echo ""
echo "  [*] OSINT rapide: $TARGET"
echo "  ========================="
echo ""

echo "=== WHOIS ==="
whois "$TARGET" 2>/dev/null | grep -iE "registrant|admin|tech|creation|expir|nameserver|email" | head -15
echo ""

echo "=== DNS Records ==="
dig ANY "$TARGET" +noall +answer 2>/dev/null
echo ""

echo "=== Subdomains (crt.sh) ==="
curl -s "https://crt.sh/?q=%25.${TARGET}&output=json" 2>/dev/null | \
    python3 -c "import sys,json;[print(x['name_value']) for x in json.load(sys.stdin)]" 2>/dev/null | \
    sort -u | head -20
echo ""

echo "=== Email pattern ==="
curl -s "https://crt.sh/?q=%25.${TARGET}&output=json" 2>/dev/null | \
    python3 -c "import sys,json;[print(x.get('name_value','')) for x in json.load(sys.stdin)]" 2>/dev/null | \
    grep "@" | sort -u | head -10
echo ""

echo "=== MX Records ==="
dig MX "$TARGET" +short 2>/dev/null
echo ""

echo "=== SPF/DMARC ==="
dig TXT "$TARGET" +short 2>/dev/null | grep -i "spf\|dmarc"
echo ""

echo "[*] Pour approfondir: shodan, theHarvester, subfinder"
echo ""
SCRIPT
chmod +x /usr/local/bin/necros-osint

mark_done "toolbox_osint"
ok "Toolbox OSINT installée"
echo ""
echo "  Commandes: necros-osint, necros-recon, whois, dig, exiftool, shodan..."
echo ""
