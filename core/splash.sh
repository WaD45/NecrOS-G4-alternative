#!/sbin/openrc-run
# shellcheck shell=sh
# ============================================================================
#  NecrOS SPLASH — Boot Animation (OpenRC service)
# ============================================================================

description="NecrOS Boot Splash"

depend() {
    after localmount
    before agetty
}

start() {
    # Only display on the first virtual console
    [ -e /dev/tty1 ] || return 0

    {
        clear

        printf '\033[1;32m'
        cat <<'SKULL'

                          ....
                        .'    ':.
                       :        ::
                      :   .  .   :
                      :  (o)(o)  :
                       :   __   :
                        :.\__/.:
                          ':::'
SKULL
        printf '\033[0m'

        printf '\033[1;36m'
        cat <<'BANNER'
    ███╗   ██╗███████╗ ██████╗██████╗  ██████╗ ███████╗
    ████╗  ██║██╔════╝██╔════╝██╔══██╗██╔═══██╗██╔════╝
    ██╔██╗ ██║█████╗  ██║     ██████╔╝██║   ██║███████╗
    ██║╚██╗██║██╔══╝  ██║     ██╔══██╗██║   ██║╚════██║
    ██║ ╚████║███████╗╚██████╗██║  ██║╚██████╔╝███████║
    ╚═╝  ╚═══╝╚══════╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
BANNER
        printf '\033[0m\n'

        _ver=$(cat /usr/local/necros/VERSION 2>/dev/null || echo "1.0.0")
        printf '    \033[1;33m"Resurrecting the Silicon Dead" — v%s\033[0m\n\n' "$_ver"

        # Progress bar
        printf '    ['
        _i=0
        while [ "$_i" -lt 30 ]; do
            printf '\033[1;32m█\033[0m'
            _i=$((_i + 1))
            # Use usleep if available, otherwise skip animation
            usleep 30000 2>/dev/null || true
        done
        printf '] \033[1;32mOK\033[0m\n\n'

        printf '    \033[1;36mBooting...\033[0m\n'
        usleep 200000 2>/dev/null || true
        printf '    \033[1;32m[✓]\033[0m Kernel: %s\n' "$(uname -r)"
        usleep 100000 2>/dev/null || true
        printf '    \033[1;32m[✓]\033[0m Arch:   %s\n' "$(uname -m)"
        usleep 100000 2>/dev/null || true
        printf '    \033[1;32m[✓]\033[0m RAM:    %sMB\n' "$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
        usleep 100000 2>/dev/null || true
        printf '    \033[1;32m[✓]\033[0m Ready\n\n'
        printf '    \033[1;33mType "startx" to enter the abyss...\033[0m\n\n'
        sleep 1

    } > /dev/tty1 2>/dev/null

    return 0
}

stop() {
    return 0
}
