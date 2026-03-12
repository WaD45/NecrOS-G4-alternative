#!/bin/sh
# ============================================================================
#  NecrOS Toolbox — Web Pentest
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
# shellcheck source=../lib/necros-common.sh
. "$_LIB" 2>/dev/null || { echo "[!] Library not found"; exit 1; }

require_root
detect_arch

necros_banner
log "Installation de la Toolbox Web Pentest..."

# --- Proxy & Interception ---
log "Proxies et intercepteurs..."
pkg_install proxychains-ng tor
pip_install mitmproxy

# --- Web scanners ---
log "Scanners web..."
pkg_install nikto
pip_install whatweb 2>/dev/null || pkg_install whatweb

# --- SQL Injection ---
log "Outils d'injection SQL..."
pip_install sqlmap

# --- Fuzzers & directory brute ---
log "Fuzzers et brute-forcers..."
pkg_install dirb
# ffuf via Go (lightweight, works on 32-bit)
if command -v go >/dev/null 2>&1; then
    go install github.com/ffuf/ffuf/v2@latest 2>/dev/null && \
        cp "$(go env GOPATH)/bin/ffuf" /usr/local/bin/ 2>/dev/null || true
fi
pkg_install gobuster

# --- Password cracking ---
log "Outils de cracking..."
pkg_install hydra john

# --- HTTP tools ---
log "Outils HTTP..."
pkg_install httpie

# --- Helper scripts ---
mkdir -p /usr/local/necros/web

cat > /usr/local/bin/necros-webrecon << 'SCRIPT'
#!/bin/sh
# NecrOS — Quick Web Reconnaissance
TARGET="$1"
[ -z "$TARGET" ] && { echo "Usage: necros-webrecon <url>"; exit 1; }

echo "[+] Reconnaissance rapide de $TARGET"
echo ""
echo "=== HTTP Headers ==="
curl -sI -m 10 "$TARGET" 2>/dev/null | head -20
echo ""
echo "=== Technologies ==="
command -v whatweb >/dev/null 2>&1 && whatweb --color=never "$TARGET" 2>/dev/null
echo ""
echo "=== robots.txt ==="
curl -s -m 5 "${TARGET}/robots.txt" 2>/dev/null | head -20
echo ""
echo "=== Security Headers ==="
curl -sI -m 10 "$TARGET" 2>/dev/null | grep -iE "x-frame|x-content|x-xss|strict-transport|content-security|referrer-policy"
echo ""
SCRIPT
chmod +x /usr/local/bin/necros-webrecon

cat > /usr/local/bin/necros-dirscan << 'SCRIPT'
#!/bin/sh
# NecrOS — Directory Scanner
TARGET="$1"
WORDLIST="${2:-/usr/share/wordlists/dirb/common.txt}"
[ -z "$TARGET" ] && { echo "Usage: necros-dirscan <url> [wordlist]"; exit 1; }

echo "[+] Scan de répertoires: $TARGET"
echo "[+] Wordlist: $WORDLIST"

if command -v ffuf >/dev/null 2>&1; then
    ffuf -u "${TARGET}/FUZZ" -w "$WORDLIST" -mc 200,301,302,403 -t 20
elif command -v gobuster >/dev/null 2>&1; then
    gobuster dir -u "$TARGET" -w "$WORDLIST" -t 20
elif command -v dirb >/dev/null 2>&1; then
    dirb "$TARGET" "$WORDLIST"
else
    echo "[!] Aucun outil de fuzzing disponible. Installez la toolbox web."
fi
SCRIPT
chmod +x /usr/local/bin/necros-dirscan

mark_done "toolbox_web"
ok "Toolbox Web Pentest installée"
echo ""
echo "  Commandes: necros-webrecon, necros-dirscan, sqlmap, hydra, nikto..."
echo ""
