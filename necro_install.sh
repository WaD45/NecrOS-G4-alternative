#!/bin/sh
# ============================================================================
#  NecrOS Installer v1.0 — "Resurrecting the Silicon Dead"
#  Le Kali du 32-bits — Ultra-light pentest OS on Alpine Linux
#
#  Usage:  sh necro_install.sh [--minimal|--full] [--no-gui] [--force]
# ============================================================================

set -e

# ---------------------------------------------------------------------------
# Bootstrap: locate the shared library
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="${SCRIPT_DIR}/lib/necros-common.sh"
if [ ! -f "$LIB" ]; then
    # Fallback: already installed
    LIB="/usr/local/necros/lib/necros-common.sh"
fi
[ -f "$LIB" ] || { echo "[✗] Cannot find necros-common.sh"; exit 1; }
# shellcheck source=lib/necros-common.sh
. "$LIB"

# ---------------------------------------------------------------------------
# CLI flags
# ---------------------------------------------------------------------------
INSTALL_MODE="standard"  # minimal | standard | full
INSTALL_GUI=1
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --minimal)  INSTALL_MODE="minimal" ;;
        --full)     INSTALL_MODE="full" ;;
        --no-gui)   INSTALL_GUI=0 ;;
        --force)    FORCE=1 ;;
        -h|--help)
            cat <<EOF
NecrOS Installer v${NECROS_VERSION}

Usage: sh necro_install.sh [OPTIONS]

Options:
  --minimal     Core tools only, no GUI, no Python extras
  --full        Everything including all toolboxes
  --no-gui      Skip X11/i3wm installation
  --force       Re-run all steps (ignore markers)
  -h, --help    Show this help

Minimum requirements:
  RAM:  256 MB (512 MB recommended)
  Disk: 500 MB (2 GB recommended for --full)
  Base: Alpine Linux 3.18+
EOF
            exit 0
            ;;
        *) warn "Option inconnue: $1" ;;
    esac
    shift
done

# Reset markers if --force
[ "$FORCE" -eq 1 ] && rm -rf "$NECROS_MARKERS" 2>/dev/null

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight() {
    necros_banner
    require_root
    require_compatible_base
    require_mem 192
    require_disk 500

    local _mem
    _mem=$(get_mem_mb)

    log "Architecture: ${NECROS_ARCH} (${NECROS_BITS}-bit)"
    log "RAM: ${_mem}MB"
    log "Disque libre: $(get_disk_free_mb /)MB"
    
    if [ "$NECROS_DISTRO" = "alpine" ]; then
        log "Système: Alpine Linux $(get_alpine_version)"
    elif [ "$NECROS_DISTRO" = "adelie" ]; then
        log "Système: Adélie Linux $(cat /etc/adelie-release 2>/dev/null || echo 'v1.0')"
    fi
    
    log "Mode: ${INSTALL_MODE} | GUI: ${INSTALL_GUI}"

    # Auto-swap on low-memory systems
    if [ "$_mem" -lt 512 ]; then
        warn "RAM < 512MB — activation du swap automatique"
        ensure_swap 256
    fi

    # Auto-downgrade to minimal on very constrained hardware
    if [ "$_mem" -lt 384 ] && [ "$INSTALL_MODE" != "minimal" ]; then
        warn "RAM < 384MB — basculement automatique en mode minimal"
        INSTALL_MODE="minimal"
        INSTALL_GUI=0
    fi
}

# ---------------------------------------------------------------------------
# Repository setup
# ---------------------------------------------------------------------------
setup_repositories() {
    if [ "$NECROS_DISTRO" = "adelie" ]; then
        log "Configuration des dépôts Adélie..."
        apk update >> "$NECROS_LOG" 2>&1
        ok "Dépôts Adélie synchronisés"
        return 0
    fi

    log "Configuration des dépôts Alpine..."

    local _ver
    _ver=$(get_alpine_version)
    [ "$_ver" = "unknown" ] && _ver="edge"

    cp /etc/apk/repositories /etc/apk/repositories.necros-bak 2>/dev/null || true

    cat > /etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${_ver}/main
https://dl-cdn.alpinelinux.org/alpine/v${_ver}/community
@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

    apk update >> "$NECROS_LOG" 2>&1
    ok "Dépôts configurés (Alpine v${_ver})"
}

# ---------------------------------------------------------------------------
# Core system packages
# ---------------------------------------------------------------------------
install_core() {
    log "Installation du noyau système..."

    pkg_install \
        build-base gcc musl-dev linux-headers \
        git curl wget \
        python3 py3-pip \
        doas \
        htop procps \
        tmux screen \
        vim nano \
        file tree jq \
        openssh-client rsync \
        coreutils findutils grep sed gawk \
        bash shadow \
        lsblk util-linux pciutils usbutils \
        ca-certificates openssl

    # doas config (idempotent)
    if [ ! -f /etc/doas.conf ] || ! grep -q "permit persist :wheel" /etc/doas.conf 2>/dev/null; then
        echo "permit persist :wheel" > /etc/doas.conf
        chmod 600 /etc/doas.conf
    fi

    ok "Noyau système installé"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
install_networking() {
    log "Installation des outils réseau..."

    pkg_install \
        nmap nmap-scripts \
        netcat-openbsd \
        tcpdump \
        iptables ip6tables nftables \
        iproute2 \
        bind-tools whois \
        traceroute mtr \
        net-tools ethtool \
        socat \
        hping3 \
        masscan \
        arp-scan \
        curl wget

    # Wireshark/tshark only if enough RAM
    if ! is_lowmem; then
        pkg_install wireshark tshark
    else
        info "RAM faible — tshark uniquement"
        pkg_install tshark
    fi

    # WiFi firmware for PPC Macs (Broadcom b43)
    if is_ppc; then
        log "PPC détecté : Installation du firmware Broadcom (WiFi)..."
        pkg_install b43-fwcutter 
        pkg_install linux-firmware-b43 2>/dev/null || true
    fi

    ok "Outils réseau installés"
}

# ---------------------------------------------------------------------------
# Python pentest libraries
# ---------------------------------------------------------------------------
install_python_tools() {
    log "Installation des bibliothèques Python pentest..."

    pip_install \
        scapy \
        requests \
        beautifulsoup4 \
        lxml \
        paramiko \
        colorama \
        tabulate \
        rich \
        pycryptodome \
        netaddr

    # Heavy tools only on 64-bit with sufficient RAM
    if ! is_32bit && ! is_lowmem; then
        pip_install pwntools impacket
    elif ! is_32bit; then
        pip_install impacket
    else
        info "32-bit: pwntools/impacket ignorés (incompatibles ou trop lourds)"
    fi

    ok "Bibliothèques Python installées"
}

# ---------------------------------------------------------------------------
# GUI: X11 + i3wm
# ---------------------------------------------------------------------------
install_gui() {
    [ "$INSTALL_GUI" -eq 0 ] && { info "GUI désactivée (--no-gui)"; return 0; }

    log "Installation de l'interface graphique..."

    # X.org base
    pkg_install \
        xorg-server xinit xrandr xset xsetroot xrdb \
        xf86-input-evdev xf86-input-libinput

    # Video drivers
    if is_ppc; then
        log "PPC détecté : Installation des pilotes vidéo spécifiques (ATI/Nouveau/FBDev)..."
        pkg_install xf86-video-fbdev xf86-video-ati xf86-video-nouveau
    else
        # Video drivers — try the generic VESA first, then fbdev (works on everything 32-bit)
        pkg_install xf86-video-vesa xf86-video-fbdev
    fi
    # Try modesetting on newer kernels
    pkg_install xf86-video-modesetting 2>/dev/null || true

    # Window manager + launcher
    pkg_install i3wm i3status i3lock dmenu rofi

    # Terminal — alacritty on 64-bit, rxvt-unicode on 32-bit (lighter)
    if is_32bit; then
        pkg_install rxvt-unicode
        NECROS_TERM="urxvt"
    else
        pkg_install rxvt-unicode
        NECROS_TERM="urxvt"
    fi
    export NECROS_TERM

    # Fonts
    pkg_install \
        terminus-font ttf-dejavu font-noto-emoji \
        font-terminus-nerd

    # Wallpaper + screenshot
    pkg_install feh scrot

    ok "Interface graphique installée (i3wm + ${NECROS_TERM})"
}

# ---------------------------------------------------------------------------
# Shell: Zsh + Oh My Zsh + custom prompt
# ---------------------------------------------------------------------------
install_shell() {
    log "Configuration du shell..."

    pkg_install zsh zsh-vcs

    # Oh My Zsh — non-interactive install
    if [ ! -d /root/.oh-my-zsh ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" \
            --unattended >> "$NECROS_LOG" 2>&1 || warn "Oh My Zsh non installé"
    fi

    # Set zsh as default shell for root
    if command -v chsh >/dev/null 2>&1; then
        chsh -s /bin/zsh root 2>/dev/null || \
            sed -i 's|root:/bin/ash|root:/bin/zsh|' /etc/passwd 2>/dev/null
    fi

    ok "Shell configuré (zsh)"
}

# ---------------------------------------------------------------------------
# Deploy NecrOS core files
# ---------------------------------------------------------------------------
deploy_necros_files() {
    log "Déploiement des fichiers NecrOS..."

    local _dest="/usr/local/necros"
    mkdir -p "$_dest"/{lib,core,toolbox,wordlists}
    mkdir -p /usr/local/bin

    # Library
    cp "$SCRIPT_DIR/lib/necros-common.sh" "$_dest/lib/"

    # VERSION
    cp "$SCRIPT_DIR/VERSION" "$_dest/"

    # Core tools
    for f in "$SCRIPT_DIR"/core/*.sh; do
        [ -f "$f" ] || continue
        cp "$f" "$_dest/core/"
        chmod +x "$_dest/core/$(basename "$f")"
    done

    # Toolbox installers
    for f in "$SCRIPT_DIR"/toolbox/*.sh; do
        [ -f "$f" ] || continue
        cp "$f" "$_dest/toolbox/"
        chmod +x "$_dest/toolbox/$(basename "$f")"
    done

    # Symlink binaries
    ln -sf "$_dest/core/vanish.sh"       /usr/local/bin/necros-vanish
    ln -sf "$_dest/core/payload.sh"      /usr/local/bin/necros-payload
    ln -sf "$_dest/core/recon.sh"        /usr/local/bin/necros-recon
    ln -sf "$_dest/core/sysinfo.sh"      /usr/local/bin/necros-sysinfo
    ln -sf "$_dest/core/update.sh"       /usr/local/bin/necros-update

    ok "Fichiers NecrOS déployés dans $_dest"
}

# ---------------------------------------------------------------------------
# Toolbox manager (improved)
# ---------------------------------------------------------------------------
create_toolbox_manager() {
    log "Création du gestionnaire de toolbox..."

    cat > /usr/local/bin/necros-toolbox << 'TOOLBOX'
#!/bin/sh
# NecrOS Toolbox Manager v1.0

_NECROS_DIR="/usr/local/necros"
. "$_NECROS_DIR/lib/necros-common.sh" 2>/dev/null || true

show_menu() {
    necros_banner
    printf '%s' "$CYAN"
    cat <<EOF
  ╔═══════════════════════════════════════╗
  ║         TOOLBOX  MANAGER             ║
  ╠═══════════════════════════════════════╣
  ║  [1]  📡  WiFi / Radio Hacking       ║
  ║  [2]  🌐  Web Pentest                ║
  ║  [3]  🔬  Reverse Engineering        ║
  ║  [4]  🛡️   Blue Team / Défense        ║
  ║  [5]  🔍  OSINT & Recon              ║
  ║  [6]  🔐  Crypto & Stego             ║
  ║  [7]  📦  Installer TOUT             ║
  ║  [8]  📋  Statut des toolboxes       ║
  ║  [0]  Quitter                        ║
  ╚═══════════════════════════════════════╝
EOF
    printf '%s' "$NC"
}

show_status() {
    echo ""
    for _tb in wifi web reverse blue osint crypto; do
        if [ -f "/var/lib/necros/markers/toolbox_${_tb}" ]; then
            printf '  %s[✓]%s %s\n' "$GREEN" "$NC" "$_tb"
        else
            printf '  %s[ ]%s %s\n' "$RED" "$NC" "$_tb"
        fi
    done
    echo ""
}

_run() {
    local _script="$_NECROS_DIR/toolbox/install_${1}.sh"
    if [ -f "$_script" ]; then
        sh "$_script"
    else
        echo "${RED}[✗] Toolbox '$1' non trouvée${NC}"
    fi
}

# Direct argument mode
case "$1" in
    wifi|1)     _run wifi ;;
    web|2)      _run web ;;
    reverse|re|3) _run reverse ;;
    blue|4)     _run blue ;;
    osint|5)    _run osint ;;
    crypto|6)   _run crypto ;;
    all|7)
        for _tb in wifi web reverse blue osint crypto; do
            _run "$_tb"
        done
        ;;
    status|8)   show_status ;;
    -h|--help)
        echo "Usage: necros-toolbox [wifi|web|reverse|blue|osint|crypto|all|status]"
        exit 0
        ;;
    "")
        # Interactive mode
        while true; do
            show_menu
            printf '  > '
            read -r _choice
            case $_choice in
                1) _run wifi ;;
                2) _run web ;;
                3) _run reverse ;;
                4) _run blue ;;
                5) _run osint ;;
                6) _run crypto ;;
                7) for _tb in wifi web reverse blue osint crypto; do _run "$_tb"; done ;;
                8) show_status ;;
                0|q) echo "💀 À bientôt, Nécromancien."; exit 0 ;;
                *) echo "Option invalide." ;;
            esac
            printf '\nAppuyez sur Entrée...'; read -r _
        done
        ;;
    *)
        echo "Usage: necros-toolbox [wifi|web|reverse|blue|osint|crypto|all|status]"
        exit 1
        ;;
esac
TOOLBOX
    chmod +x /usr/local/bin/necros-toolbox

    ok "Gestionnaire de toolbox créé"
}

# ---------------------------------------------------------------------------
# Theme configuration
# ---------------------------------------------------------------------------
configure_theme() {
    [ "$INSTALL_GUI" -eq 0 ] && return 0

    log "Application du thème NecrOS..."

    # --- Xresources (urxvt) ---
    cat > /root/.Xresources << 'XRES'
! NecrOS Terminal Theme — "The Necromancer"
URxvt.scrollBar:       false
URxvt.font:            xft:Terminus:size=12:antialias=true
URxvt.boldFont:        xft:Terminus:bold:size=12:antialias=true
URxvt.cursorBlink:     true
URxvt.saveline:        10000
URxvt.urgentOnBell:    true
URxvt.perl-ext-common: default,matcher
URxvt.url-launcher:    /usr/bin/xdg-open
URxvt.matcher.button:  1

! Colour scheme: Necromancer (green on black)
URxvt*background:  #0a0a0a
URxvt*foreground:  #00ff41
URxvt*cursorColor: #00ff41
URxvt*color0:  #0a0a0a
URxvt*color8:  #3d3d3d
URxvt*color1:  #ff5c57
URxvt*color9:  #ff6e67
URxvt*color2:  #00ff41
URxvt*color10: #5af78e
URxvt*color3:  #f3f99d
URxvt*color11: #f4f99d
URxvt*color4:  #57c7ff
URxvt*color12: #57c7ff
URxvt*color5:  #ff6ac1
URxvt*color13: #ff6ac1
URxvt*color6:  #9aedfe
URxvt*color14: #9aedfe
URxvt*color7:  #c7c7c7
URxvt*color15: #ffffff
XRES

    # --- i3 config ---
    mkdir -p /root/.config/i3
    cat > /root/.config/i3/config << 'I3CONF'
# NecrOS i3 Configuration v1.0
set $mod Mod4
font pango:Terminus 10

# Colours
set $bg      #0a0a0a
set $ibg     #1a1a1a
set $fg      #00ff41
set $ifg     #666666
set $urgent  #ff5c57

client.focused          $bg  $bg  $fg  #00ff41
client.unfocused        $ibg $ibg $ifg #1a1a1a
client.focused_inactive $ibg $ibg $ifg #1a1a1a
client.urgent           $urgent $urgent $fg #ff5c57

default_border pixel 2
default_floating_border pixel 2
gaps inner 4
gaps outer 2

# Keybindings — essentials
bindsym $mod+Return exec urxvt
bindsym $mod+Shift+q kill
bindsym $mod+d exec --no-startup-id rofi -show run -theme /root/.config/rofi/necros.rasi
bindsym $mod+space exec --no-startup-id dmenu_run -nb '#0a0a0a' -nf '#00ff41' -sb '#00ff41' -sf '#0a0a0a'

# Navigation (vim-style + arrows)
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# Move windows
bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

# Layout
bindsym $mod+b split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split
bindsym $mod+Shift+space floating toggle

# Workspaces
set $ws1 "1:term"
set $ws2 "2:recon"
set $ws3 "3:exploit"
set $ws4 "4:defense"
set $ws5 "5:web"
set $ws6 "6"
set $ws7 "7"
set $ws8 "8"
set $ws9 "9"
set $ws10 "10"

bindsym $mod+1 workspace $ws1
bindsym $mod+2 workspace $ws2
bindsym $mod+3 workspace $ws3
bindsym $mod+4 workspace $ws4
bindsym $mod+5 workspace $ws5
bindsym $mod+6 workspace $ws6
bindsym $mod+7 workspace $ws7
bindsym $mod+8 workspace $ws8
bindsym $mod+9 workspace $ws9
bindsym $mod+0 workspace $ws10

bindsym $mod+Shift+1 move container to workspace $ws1
bindsym $mod+Shift+2 move container to workspace $ws2
bindsym $mod+Shift+3 move container to workspace $ws3
bindsym $mod+Shift+4 move container to workspace $ws4
bindsym $mod+Shift+5 move container to workspace $ws5
bindsym $mod+Shift+6 move container to workspace $ws6
bindsym $mod+Shift+7 move container to workspace $ws7
bindsym $mod+Shift+8 move container to workspace $ws8
bindsym $mod+Shift+9 move container to workspace $ws9
bindsym $mod+Shift+0 move container to workspace $ws10

# System
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Quitter NecrOS?' -B 'Oui' 'i3-msg exit'"
bindsym $mod+Escape exec i3lock -c 0a0a0a
bindsym Print exec scrot ~/screenshots/%Y-%m-%d_%H-%M-%S.png

# Volume
bindsym XF86AudioRaiseVolume exec amixer set Master 5%+
bindsym XF86AudioLowerVolume exec amixer set Master 5%-
bindsym XF86AudioMute exec amixer set Master toggle

# Resize
mode "resize" {
    bindsym h resize shrink width 10 px or 10 ppt
    bindsym j resize grow height 10 px or 10 ppt
    bindsym k resize shrink height 10 px or 10 ppt
    bindsym l resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# Status bar
bar {
    status_command i3status -c /root/.config/i3/i3status.conf
    position top
    colors {
        background #0a0a0a
        statusline #00ff41
        separator  #3d3d3d
        focused_workspace  #00ff41 #00ff41 #0a0a0a
        active_workspace   #1a1a1a #1a1a1a #00ff41
        inactive_workspace #0a0a0a #0a0a0a #666666
        urgent_workspace   #ff5c57 #ff5c57 #ffffff
    }
}

# Autostart
exec --no-startup-id xrdb -merge ~/.Xresources
exec --no-startup-id xsetroot -solid '#0a0a0a'
I3CONF

    # --- i3status ---
    cat > /root/.config/i3/i3status.conf << 'I3STAT'
general {
    colors = true
    color_good = "#00ff41"
    color_degraded = "#f3f99d"
    color_bad = "#ff5c57"
    interval = 5
}
order += "wireless _first_"
order += "ethernet _first_"
order += "disk /"
order += "cpu_usage"
order += "memory"
order += "tztime local"

wireless _first_ {
    format_up = "W:%essid %quality"
    format_down = "W:down"
}
ethernet _first_ {
    format_up = "E:%ip"
    format_down = "E:down"
}
disk "/" {
    format = "D:%avail"
}
cpu_usage {
    format = "C:%usage"
}
memory {
    format = "M:%used"
    threshold_degraded = "10%"
}
tztime local {
    format = "%Y-%m-%d %H:%M"
}
I3STAT

    # --- Rofi ---
    mkdir -p /root/.config/rofi
    cat > /root/.config/rofi/necros.rasi << 'ROFI'
* {
    background: #0a0a0a;
    foreground: #00ff41;
    border-color: #00ff41;
    selected-background: #00ff41;
    selected-foreground: #0a0a0a;
}
window {
    background-color: @background;
    border: 2px;
    border-color: @border-color;
    padding: 10px;
}
mainbox { children: [inputbar, listview]; }
inputbar { children: [prompt, entry]; background-color: @background; }
prompt { background-color: @background; text-color: @foreground; padding: 5px; }
entry { background-color: @background; text-color: @foreground; padding: 5px; }
listview { background-color: @background; columns: 1; }
element { background-color: @background; text-color: @foreground; padding: 5px; }
element selected { background-color: @selected-background; text-color: @selected-foreground; }
ROFI

    # --- xinitrc ---
    cat > /root/.xinitrc << 'XINIT'
#!/bin/sh
xrdb -merge ~/.Xresources
xsetroot -solid '#0a0a0a'
xset s off
xset -dpms
exec i3
XINIT
    chmod +x /root/.xinitrc

    ok "Thème NecrOS appliqué"
}

# ---------------------------------------------------------------------------
# Zsh configuration
# ---------------------------------------------------------------------------
configure_zshrc() {
    log "Configuration zshrc..."

    cat > /root/.zshrc << 'ZSHRC'
# NecrOS ZSH Configuration v1.0

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git sudo history colored-man-pages)
[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# Fallback prompt when oh-my-zsh is not present
if [ ! -d "$ZSH" ]; then
    autoload -U colors && colors
    PROMPT='%{$fg[green]%}[necros]%{$reset_color%} %{$fg[cyan]%}%n%{$reset_color%}:%{$fg[yellow]%}%~%{$reset_color%}
%{$fg[green]%}> %{$reset_color%}'
fi

# --- Aliases: System ---
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# --- Aliases: Networking ---
alias scan='nmap -sV -sC'
alias fastscan='nmap -F -T4'
alias fullscan='nmap -p- -sV -sC -T4'
alias pingsweep='nmap -sn'
alias listen='nc -lvnp'
alias serve='python3 -m http.server 8888'
alias sniff='tcpdump -i any -w'
alias myip='curl -s ifconfig.me'
alias localip='ip -4 addr show | grep -oP "(?<=inet )[\d.]+" | grep -v 127.0.0.1'
alias ports='ss -tlnp'

# --- Aliases: NecrOS ---
alias vanish='doas necros-vanish'
alias payload='necros-payload'
alias recon='necros-recon'
alias toolbox='doas necros-toolbox'
alias sysinfo='necros-sysinfo'

# Environment
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export TERM=xterm-256color
export NECROS_VERSION="$(cat /usr/local/necros/VERSION 2>/dev/null || echo '1.0.0')"

# History
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY
setopt AUTO_CD CORRECT EXTENDED_GLOB

# Wordlists shortcut
export WORDLISTS="/usr/share/wordlists"

# Banner
printf '\n  \033[0;32m[necros]\033[0m v%s — %s (%s-bit) — %s MB RAM\n\n' \
    "$NECROS_VERSION" "$(uname -m)" \
    "$(getconf LONG_BIT 2>/dev/null || echo '?')" \
    "$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
ZSHRC

    ok "zshrc configuré"
}

# ---------------------------------------------------------------------------
# Boot splash (OpenRC service)
# ---------------------------------------------------------------------------
install_splash() {
    log "Installation du splash de boot..."

    cp "$SCRIPT_DIR/core/splash.sh" /etc/init.d/necros-splash 2>/dev/null || \
        cp /usr/local/necros/core/splash.sh /etc/init.d/necros-splash 2>/dev/null || {
            warn "splash.sh non trouvé, skip"
            return 0
        }
    chmod +x /etc/init.d/necros-splash
    rc-update add necros-splash default 2>/dev/null || true

    ok "Splash de boot installé"
}

# ---------------------------------------------------------------------------
# Welcome message (TTY login)
# ---------------------------------------------------------------------------
create_welcome() {
    cat > /etc/profile.d/necros-welcome.sh << 'WELCOME'
#!/bin/sh
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    clear
    . /usr/local/necros/lib/necros-common.sh 2>/dev/null
    necros_banner 2>/dev/null || cat <<'B'
    _   _           ___  ___
   | \ | |         / _ \/ __|
   |  \| | ___ ___| | | \__ \
   | |\  |/ -_) __| |_| |__) |
   |_| \_|\___|\___|___/|___/
B
    echo "  Commandes: startx | necros-toolbox | necros-sysinfo"
    echo ""
fi
WELCOME
    chmod +x /etc/profile.d/necros-welcome.sh
}

# ---------------------------------------------------------------------------
# Wordlists (minimal set, disk-conscious)
# ---------------------------------------------------------------------------
install_wordlists() {
    log "Installation des wordlists de base..."

    local _wl="/usr/share/wordlists"
    mkdir -p "$_wl"

    # SecLists — only the essentials (not the full 1GB+ repo)
    if [ ! -f "$_wl/rockyou.txt.gz" ] && [ ! -f "$_wl/rockyou.txt" ]; then
        info "Téléchargement de rockyou.txt.gz..."
        wget -q "https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt" \
            -O "$_wl/rockyou.txt" 2>/dev/null && \
            gzip "$_wl/rockyou.txt" 2>/dev/null || \
            warn "rockyou.txt non téléchargé"
    fi

    # Quick small wordlists
    if [ ! -d "$_wl/dirb" ]; then
        mkdir -p "$_wl/dirb"
        wget -q "https://raw.githubusercontent.com/v0re/dirb/master/wordlists/common.txt" \
            -O "$_wl/dirb/common.txt" 2>/dev/null || warn "dirb/common.txt non téléchargé"
    fi

    ok "Wordlists installées dans $_wl"
}

# ---------------------------------------------------------------------------
# Full mode: install all toolboxes
# ---------------------------------------------------------------------------
install_all_toolboxes() {
    [ "$INSTALL_MODE" != "full" ] && return 0

    log "Mode full: installation de toutes les toolboxes..."
    for _tb in wifi web reverse blue osint crypto; do
        local _script="/usr/local/necros/toolbox/install_${_tb}.sh"
        if [ -f "$_script" ]; then
            sh "$_script" || warn "Toolbox $_tb: erreurs rencontrées"
        fi
    done
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
    log "Nettoyage..."
    apk cache clean 2>/dev/null || true
    rm -rf /tmp/necros-* 2>/dev/null || true
    ok "Nettoyage terminé"
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
finish() {
    printf '\n%s' "$GREEN"
    cat << 'FIN'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║   NECROS v1.0 — INSTALLATION TERMINÉE                    ║
    ║                                                           ║
    ║   Commandes:                                              ║
    ║     startx              Lancer l'interface graphique      ║
    ║     necros-toolbox      Installer des outils              ║
    ║     necros-recon        Reconnaissance automatisée        ║
    ║     necros-payload      Générateur de payloads            ║
    ║     necros-vanish       Effacer les traces                ║
    ║     necros-sysinfo      Informations système              ║
    ║     necros-update       Mettre à jour NecrOS              ║
    ║                                                           ║
    ║   i3 raccourcis:                                          ║
    ║     Super+Enter         Terminal                          ║
    ║     Super+D             Menu applications                 ║
    ║     Super+Shift+Q       Fermer fenêtre                    ║
    ║                                                           ║
    ║   Bienvenue dans l'abysse, Nécromancien.                  ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
FIN
    printf '%s\n' "$NC"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    preflight

    run_once "repositories"     setup_repositories
    run_once "core_packages"    install_core
    run_once "networking"       install_networking
    run_once "python_tools"     install_python_tools
    run_once "gui"              install_gui
    run_once "shell"            install_shell
    run_once "deploy_files"     deploy_necros_files
    run_once "toolbox_manager"  create_toolbox_manager
    run_once "theme"            configure_theme
    run_once "zshrc"            configure_zshrc
    run_once "splash"           install_splash
    run_once "welcome"          create_welcome
    run_once "wordlists"        install_wordlists

    # Full mode installs all toolboxes
    install_all_toolboxes

    cleanup
    finish

    log "Installation NecrOS v${NECROS_VERSION} terminée — mode: ${INSTALL_MODE}"
}

main "$@"
