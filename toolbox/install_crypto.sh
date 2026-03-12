#!/bin/sh
# ============================================================================
#  NecrOS Toolbox — Crypto & Steganography
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="${SCRIPT_DIR}/../lib/necros-common.sh"
[ -f "$_LIB" ] || _LIB="/usr/local/necros/lib/necros-common.sh"
. "$_LIB" 2>/dev/null || { echo "[!] Library not found"; exit 1; }

require_root
detect_arch

necros_banner
log "Installation de la Toolbox Crypto & Stego..."

# --- Cryptography ---
log "Outils cryptographiques..."
pkg_install openssl gnupg

# --- Python crypto libs ---
log "Bibliothèques Python crypto..."
pip_install pycryptodome cryptography hashlib-additional 2>/dev/null
pip_install pycryptodome cryptography

# --- Steganography ---
log "Outils de stéganographie..."
pkg_install steghide
pip_install stegano 2>/dev/null || info "stegano non disponible"

# --- Image analysis ---
pkg_install imagemagick exiftool

# --- Hash tools ---
log "Outils de hash..."
pkg_install john

# --- Encoding tools ---
log "Outils d'encodage..."
pkg_install base64 2>/dev/null || true  # Usually part of coreutils

# --- Helper script ---
cat > /usr/local/bin/necros-crypt << 'SCRIPT'
#!/bin/sh
# NecrOS — Crypto Swiss Army Knife

show_help() {
    cat <<EOF
NecrOS Crypto Toolkit

Usage: necros-crypt <command> [args]

Commands:
  hash <file>              Show all hashes of a file
  b64enc <string>          Base64 encode
  b64dec <string>          Base64 decode
  rot13 <string>           ROT13
  hexenc <string>          String to hex
  hexdec <hex>             Hex to string
  identify <hash>          Guess hash type
  genpass [length]         Generate random password
  encrypt <file>           AES-256 encrypt file
  decrypt <file.enc>       Decrypt file
EOF
}

case "$1" in
    hash)
        [ -z "$2" ] && { echo "Usage: necros-crypt hash <file>"; exit 1; }
        echo "MD5:    $(md5sum "$2" | cut -d' ' -f1)"
        echo "SHA1:   $(sha1sum "$2" | cut -d' ' -f1)"
        echo "SHA256: $(sha256sum "$2" | cut -d' ' -f1)"
        echo "SHA512: $(sha512sum "$2" | cut -d' ' -f1)"
        ;;
    b64enc)
        shift; printf '%s' "$*" | base64
        ;;
    b64dec)
        shift; printf '%s' "$*" | base64 -d 2>/dev/null; echo
        ;;
    rot13)
        shift; printf '%s' "$*" | tr 'A-Za-z' 'N-ZA-Mn-za-m'; echo
        ;;
    hexenc)
        shift; printf '%s' "$*" | xxd -p; echo
        ;;
    hexdec)
        shift; printf '%s' "$*" | xxd -r -p; echo
        ;;
    identify)
        shift
        _h="$*"
        _len=${#_h}
        echo "Hash: $_h"
        echo "Length: $_len characters"
        case "$_len" in
            32) echo "Possible: MD5, NTLM" ;;
            40) echo "Possible: SHA-1" ;;
            56) echo "Possible: SHA-224" ;;
            64) echo "Possible: SHA-256, SHA3-256" ;;
            96) echo "Possible: SHA-384" ;;
            128) echo "Possible: SHA-512, SHA3-512" ;;
            *) echo "Unknown hash type (length $_len)" ;;
        esac
        ;;
    genpass)
        _len="${2:-32}"
        openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c "$_len"; echo
        ;;
    encrypt)
        [ -z "$2" ] && { echo "Usage: necros-crypt encrypt <file>"; exit 1; }
        openssl enc -aes-256-cbc -salt -pbkdf2 -in "$2" -out "${2}.enc"
        echo "[✓] Encrypted: ${2}.enc"
        ;;
    decrypt)
        [ -z "$2" ] && { echo "Usage: necros-crypt decrypt <file.enc>"; exit 1; }
        _out=$(echo "$2" | sed 's/\.enc$//')
        [ "$_out" = "$2" ] && _out="${2}.dec"
        openssl enc -aes-256-cbc -d -pbkdf2 -in "$2" -out "$_out"
        echo "[✓] Decrypted: $_out"
        ;;
    -h|--help|"")
        show_help
        ;;
    *)
        echo "[!] Commande inconnue: $1"
        show_help
        exit 1
        ;;
esac
SCRIPT
chmod +x /usr/local/bin/necros-crypt

mark_done "toolbox_crypto"
ok "Toolbox Crypto & Stego installée"
echo ""
echo "  Commandes: necros-crypt, openssl, steghide, john, exiftool..."
echo ""
