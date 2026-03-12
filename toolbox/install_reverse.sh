#!/bin/sh
# ============================================================================
#  NecrOS Toolbox — Reverse Engineering
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
. "$_LIB" 2>/dev/null || { echo "[!] Library not found"; exit 1; }

require_root
detect_arch

necros_banner
log "Installation de la Toolbox Reverse Engineering..."

# --- Debuggers ---
log "Debuggers..."
pkg_install gdb strace ltrace

# GEF (GDB Enhanced Features)
if [ ! -f /root/.gef.py ]; then
    info "Installation de GEF..."
    wget -q "https://raw.githubusercontent.com/hugsy/gef/main/gef.py" \
        -O /root/.gef.py 2>/dev/null && {
        echo "source ~/.gef.py" > /root/.gdbinit
        ok "GEF installé"
    } || warn "GEF non installé (pas de réseau?)"
fi

# --- Disassemblers ---
log "Désassembleurs..."
pkg_install objdump binutils

# radare2 — from source on 32-bit (APK version may not exist)
if ! command -v r2 >/dev/null 2>&1; then
    if pkg_installed radare2; then
        : # already there
    elif ! is_lowmem; then
        info "Compilation de radare2 depuis les sources..."
        _tmp="/tmp/necros-r2-$$"
        mkdir -p "$_tmp"
        if git clone --depth 1 https://github.com/radareorg/radare2.git "$_tmp/r2" >> "$NECROS_LOG" 2>&1; then
            cd "$_tmp/r2" && sys/install.sh >> "$NECROS_LOG" 2>&1 && ok "radare2 compilé et installé" || \
                warn "Compilation de radare2 échouée"
            cd /
        fi
        rm -rf "$_tmp"
    else
        warn "RAM insuffisante pour compiler radare2"
    fi
fi

# --- Hex editors ---
log "Éditeurs hexadécimaux..."
pkg_install hexedit xxd

# --- Binary analysis ---
log "Analyse de binaires..."
pkg_install binwalk file

# --- Python tools ---
log "Outils Python RE..."
if ! is_32bit; then
    pip_install pwntools ropper
else
    pip_install ropper
    info "32-bit: pwntools ignoré"
fi

# --- Helper scripts ---
cat > /usr/local/bin/necros-bininfo << 'SCRIPT'
#!/bin/sh
# NecrOS — Quick Binary Analysis
BIN="$1"
[ -z "$BIN" ] || [ ! -f "$BIN" ] && { echo "Usage: necros-bininfo <binary>"; exit 1; }
echo "=== File Type ==="
file "$BIN"
echo ""
echo "=== Checksec ==="
if command -v checksec >/dev/null 2>&1; then
    checksec --file="$BIN" 2>/dev/null
else
    readelf -h "$BIN" 2>/dev/null | grep -E "Type|Machine|Entry"
    readelf -l "$BIN" 2>/dev/null | grep -i "gnu_stack"
fi
echo ""
echo "=== Strings (first 20) ==="
strings "$BIN" | head -20
echo ""
echo "=== Shared Libraries ==="
ldd "$BIN" 2>/dev/null || readelf -d "$BIN" 2>/dev/null | grep NEEDED
echo ""
SCRIPT
chmod +x /usr/local/bin/necros-bininfo

# --- Pwntools template ---
mkdir -p /usr/local/necros/re
cat > /usr/local/necros/re/pwn_template.py << 'PYTEMPLATE'
#!/usr/bin/env python3
"""NecrOS pwntools exploit template."""
from pwn import *

# --- Config ---
BINARY = "./vuln"
REMOTE = ("target.com", 1337)
# context.log_level = "debug"

elf = ELF(BINARY)
# libc = ELF("./libc.so.6")
# rop = ROP(elf)

def exploit(io):
    # --- Exploit logic here ---
    payload = b"A" * 64
    payload += p32(elf.symbols["win"])  # or p64 for 64-bit

    io.sendlineafter(b"> ", payload)
    io.interactive()

if __name__ == "__main__":
    if args.REMOTE:
        io = remote(*REMOTE)
    else:
        io = process(BINARY)
    exploit(io)
PYTEMPLATE

mark_done "toolbox_reverse"
ok "Toolbox Reverse Engineering installée"
echo ""
echo "  Commandes: gdb (with GEF), r2, necros-bininfo, strace, ltrace..."
echo ""
