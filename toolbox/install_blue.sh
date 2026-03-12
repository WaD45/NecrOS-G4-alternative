#!/bin/sh
# ============================================================================
#  NecrOS Toolbox — Blue Team / Défense
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
. "$_LIB" 2>/dev/null || { echo "[!] Library not found"; exit 1; }

require_root
detect_arch

necros_banner
log "Installation de la Toolbox Blue Team..."

# --- IDS / IPS ---
log "IDS/IPS..."
pkg_install suricata fail2ban

# --- Rootkit detection ---
log "Détection de rootkits..."
pkg_install rkhunter chkrootkit

# --- Antivirus ---
log "Antivirus..."
if ! is_lowmem; then
    pkg_install clamav
else
    info "RAM faible: ClamAV ignoré"
fi

# --- YARA ---
log "YARA rules engine..."
pkg_install yara
pip_install yara-python

# --- Log analysis ---
log "Analyse de logs..."
pkg_install logrotate lnav goaccess

# --- Network monitoring ---
log "Monitoring réseau..."
pkg_install iftop nethogs bmon

# --- Security audit ---
log "Audit de sécurité..."
pkg_install lynis

# --- Forensics basics ---
log "Outils forensics de base..."
pkg_install sleuthkit foremost

# --- Helper scripts ---
cat > /usr/local/bin/necros-seccheck << 'SCRIPT'
#!/bin/sh
# NecrOS — Quick Security Check
echo ""
echo "  [*] NecrOS Security Check"
echo "  ========================="
echo ""
echo "=== Listening Ports ==="
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
echo ""
echo "=== Active Connections ==="
ss -tnp 2>/dev/null | grep ESTAB | head -10
echo ""
echo "=== Failed Logins (last 10) ==="
grep -i "failed\|invalid" /var/log/auth.log 2>/dev/null | tail -10
echo ""
echo "=== SUID Binaries ==="
find / -perm -4000 -type f 2>/dev/null | head -20
echo ""
echo "=== World-writable Files ==="
find /etc /usr -perm -o+w -type f 2>/dev/null | head -10
echo ""
echo "=== Cron Jobs ==="
for u in $(cut -d: -f1 /etc/passwd); do
    crontab -l -u "$u" 2>/dev/null | grep -v "^#" | grep -v "^$" | while read -r line; do
        printf '  %s: %s\n' "$u" "$line"
    done
done
echo ""
SCRIPT
chmod +x /usr/local/bin/necros-seccheck

cat > /usr/local/bin/necros-audit << 'SCRIPT'
#!/bin/sh
# NecrOS — Security Audit (Lynis wrapper)
if command -v lynis >/dev/null 2>&1; then
    lynis audit system --quick
else
    echo "[!] Lynis non installé. Lancez: necros-toolbox blue"
fi
SCRIPT
chmod +x /usr/local/bin/necros-audit

# --- Basic YARA rules ---
mkdir -p /usr/local/necros/blue/yara
cat > /usr/local/necros/blue/yara/suspicious.yar << 'YARRULE'
rule SuspiciousShell {
    meta:
        description = "Detects common webshell patterns"
        author = "NecrOS"
    strings:
        $s1 = "system($_GET" nocase
        $s2 = "shell_exec(" nocase
        $s3 = "passthru(" nocase
        $s4 = "eval(base64_decode" nocase
        $s5 = "exec($_REQUEST" nocase
    condition:
        any of them
}

rule SuspiciousEncoding {
    meta:
        description = "Detects base64-encoded payloads"
        author = "NecrOS"
    strings:
        $s1 = "base64_decode" nocase
        $s2 = "gzinflate" nocase
        $s3 = "str_rot13" nocase
    condition:
        2 of them
}
YARRULE

mark_done "toolbox_blue"
ok "Toolbox Blue Team installée"
echo ""
echo "  Commandes: necros-seccheck, necros-audit, suricata, fail2ban, lynis..."
echo ""
