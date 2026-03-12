#!/bin/sh
# ============================================================================
#  NecrOS SYSINFO v1.0 — System Information Dashboard
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
# shellcheck source=../lib/necros-common.sh
. "$_LIB" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
}

necros_banner 2>/dev/null

_hr() { printf '%s────────────────────────────────────────────%s\n' "$CYAN" "$NC"; }

# --- System ---
_hr
printf '%s SYSTEM %s\n' "$BOLD" "$NC"
printf '  OS:           %s\n' "NecrOS v$(cat /usr/local/necros/VERSION 2>/dev/null || echo '?')"
printf '  Base:         %s\n' "Alpine Linux $(cat /etc/alpine-release 2>/dev/null || echo '?')"
printf '  Kernel:       %s\n' "$(uname -r)"
printf '  Architecture: %s (%s-bit)\n' "$(uname -m)" "$(getconf LONG_BIT 2>/dev/null || echo '?')"
printf '  Hostname:     %s\n' "$(hostname)"
printf '  Uptime:       %s\n' "$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | sed 's/,.*load.*//')"

# --- Hardware ---
_hr
printf '%s HARDWARE %s\n' "$BOLD" "$NC"
_mem_total=$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)
_mem_avail=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo)
_mem_used=$((_mem_total - _mem_avail))
_mem_pct=$((_mem_used * 100 / _mem_total))
printf '  RAM:          %sMB / %sMB (%s%% used)\n' "$_mem_used" "$_mem_total" "$_mem_pct"

_swap=$(swapon --show --noheadings 2>/dev/null | awk '{print $3}' | head -1)
printf '  Swap:         %s\n' "${_swap:-none}"

_cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //')
_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
printf '  CPU:          %s (%s cores)\n' "${_cpu:-unknown}" "${_cores:-?}"

_disk_total=$(df -h / | awk 'NR==2{print $2}')
_disk_used=$(df -h / | awk 'NR==2{print $3}')
_disk_avail=$(df -h / | awk 'NR==2{print $4}')
_disk_pct=$(df / | awk 'NR==2{print $5}')
printf '  Disk (/):     %s / %s (%s free, %s used)\n' "$_disk_used" "$_disk_total" "$_disk_avail" "$_disk_pct"

# --- Network ---
_hr
printf '%s NETWORK %s\n' "$BOLD" "$NC"
ip -4 addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | while read -r _line; do
    _ip=$(echo "$_line" | awk '{print $2}')
    _iface=$(echo "$_line" | awk '{print $NF}')
    printf '  Interface:    %s → %s\n' "$_iface" "$_ip"
done

_gateway=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
printf '  Gateway:      %s\n' "${_gateway:-none}"

_dns=$(grep nameserver /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
printf '  DNS:          %s\n' "${_dns:-none}"

_pub_ip=$(curl -s -m 3 ifconfig.me 2>/dev/null)
printf '  Public IP:    %s\n' "${_pub_ip:-unavailable}"

# --- Security Tools ---
_hr
printf '%s NECROS TOOLS %s\n' "$BOLD" "$NC"
_check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        printf '  %s[✓]%s %s\n' "$GREEN" "$NC" "$2"
    else
        printf '  %s[ ]%s %s\n' "$RED" "$NC" "$2"
    fi
}

_check_cmd nmap "nmap"
_check_cmd tcpdump "tcpdump"
_check_cmd aircrack-ng "aircrack-ng"
_check_cmd sqlmap "sqlmap"
_check_cmd gdb "gdb"
_check_cmd radare2 "radare2"
_check_cmd suricata "suricata"
_check_cmd hydra "hydra"
_check_cmd john "john"
_check_cmd ffuf "ffuf"
_check_cmd mitmproxy "mitmproxy"
_check_cmd whatweb "whatweb"

# --- Toolbox Status ---
_hr
printf '%s TOOLBOXES %s\n' "$BOLD" "$NC"
for _tb in wifi web reverse blue osint crypto; do
    if [ -f "/var/lib/necros/markers/toolbox_${_tb}" ]; then
        printf '  %s[✓]%s %s\n' "$GREEN" "$NC" "$_tb"
    else
        printf '  %s[ ]%s %s\n' "$RED" "$NC" "$_tb"
    fi
done

_hr
echo ""
