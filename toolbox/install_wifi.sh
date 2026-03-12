#!/bin/sh
# ============================================================================
#  NecrOS Toolbox — WiFi / Radio Hacking
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
# shellcheck source=../lib/necros-common.sh
. "$_LIB" 2>/dev/null || { echo "[!] Library not found"; exit 1; }

require_root
detect_arch

necros_banner
log "Installation de la Toolbox WiFi/Radio..."

# --- WiFi core ---
log "Outils WiFi de base..."
pkg_install aircrack-ng iw wireless-tools wpa_supplicant hostapd macchanger reaver

# --- Bluetooth ---
log "Outils Bluetooth..."
pkg_install bluez bluez-utils

# --- Hashcat (64-bit + enough RAM only) ---
if ! is_32bit; then
    _mem=$(get_mem_mb)
    if [ "$_mem" -gt 1024 ]; then
        log "Installation de hashcat..."
        pkg_install hashcat
    else
        info "RAM < 1GB: hashcat ignoré"
    fi
else
    info "32-bit: hashcat ignoré (non supporté)"
fi

# --- SDR (Software Defined Radio) ---
log "Outils SDR..."
pkg_install rtl-sdr
if ! is_32bit && ! is_lowmem; then
    pkg_install gnuradio gqrx
fi

# --- udev rules for RTL-SDR ---
if [ -d "/etc/udev/rules.d" ]; then
    cat > /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE:="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE:="0666"
EOF
fi

# --- Python wireless ---
pip_install scapy

# --- Helper scripts ---
mkdir -p /usr/local/necros/wifi

cat > /usr/local/bin/necros-monitor << 'SCRIPT'
#!/bin/sh
# NecrOS — Mode Monitor Helper
if [ $# -lt 2 ]; then
    echo "Usage: necros-monitor <interface> <start|stop>"
    echo "  Ex: necros-monitor wlan0 start"
    exit 1
fi
IFACE="$1"; ACTION="$2"
case "$ACTION" in
    start)
        echo "[+] Activation mode monitor sur $IFACE..."
        ip link set "$IFACE" down
        iw dev "$IFACE" set type monitor
        ip link set "$IFACE" up
        echo "[✓] Mode monitor activé sur $IFACE"
        ;;
    stop)
        echo "[+] Retour en mode managed sur $IFACE..."
        ip link set "$IFACE" down
        iw dev "$IFACE" set type managed
        ip link set "$IFACE" up
        echo "[✓] Mode managed restauré sur $IFACE"
        ;;
    *) echo "Action invalide: $ACTION (start|stop)"; exit 1 ;;
esac
SCRIPT
chmod +x /usr/local/bin/necros-monitor

cat > /usr/local/bin/necros-wifiscan << 'SCRIPT'
#!/bin/sh
# NecrOS — WiFi Scanner
IFACE="${1:-wlan0}"
echo "[+] Scan WiFi sur $IFACE..."
MODE=$(iw dev "$IFACE" info 2>/dev/null | grep type | awk '{print $2}')
if [ "$MODE" = "monitor" ]; then
    airodump-ng "$IFACE"
else
    echo "[!] Interface pas en mode monitor. Scan passif via iw..."
    iw dev "$IFACE" scan 2>/dev/null | grep -E "SSID|signal|BSS" | head -50
    echo ""
    echo "[*] Pour un scan complet: necros-monitor $IFACE start && necros-wifiscan $IFACE"
fi
SCRIPT
chmod +x /usr/local/bin/necros-wifiscan

mark_done "toolbox_wifi"
ok "Toolbox WiFi/Radio installée"
echo ""
echo "  Commandes: necros-monitor, necros-wifiscan, aircrack-ng, reaver..."
echo ""
