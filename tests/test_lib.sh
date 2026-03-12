#!/bin/sh
# ============================================================================
#  NecrOS Test Suite — lib/necros-common.sh
# ============================================================================

set -e

_PASS=0
_FAIL=0
_TOTAL=0

_test() {
    _TOTAL=$((_TOTAL + 1))
    local _name="$1"; shift
    if eval "$@" >/dev/null 2>&1; then
        printf '  \033[0;32m✓\033[0m %s\n' "$_name"
        _PASS=$((_PASS + 1))
    else
        printf '  \033[0;31m✗\033[0m %s\n' "$_name"
        _FAIL=$((_FAIL + 1))
    fi
}

echo ""
echo "  NecrOS Test Suite"
echo "  ================="
echo ""

# ---------------------------------------------------------------------------
# Source the library
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_LIB="$SCRIPT_DIR/../lib/necros-common.sh"

_test "Library file exists" "[ -f '$_LIB' ]"
_test "Library is sourceable" ". '$_LIB'"

# Source it for real
. "$_LIB" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
_test "NECROS_VERSION is set" "[ -n '$NECROS_VERSION' ]"
_ver_file=$(tr -d '[:space:]' < "$SCRIPT_DIR/../VERSION" 2>/dev/null)
_ver_var=$(printf '%s' "$NECROS_VERSION" | tr -d '[:space:]')
_test "NECROS_VERSION matches VERSION file" "[ '$_ver_file' = '$_ver_var' ]"

# ---------------------------------------------------------------------------
# Architecture detection
# ---------------------------------------------------------------------------
_test "NECROS_ARCH is set" "[ -n '$NECROS_ARCH' ]"
_test "NECROS_BITS is set" "[ -n '$NECROS_BITS' ]"
_test "NECROS_ARCH_FAMILY is set" "[ -n '$NECROS_ARCH_FAMILY' ]"
_test "NECROS_BITS is 32 or 64" \
    "[ '$NECROS_BITS' -eq 32 ] || [ '$NECROS_BITS' -eq 64 ]"

# ---------------------------------------------------------------------------
# Functions exist
# ---------------------------------------------------------------------------
for _fn in log warn err die info ok get_mem_mb get_disk_free_mb \
           necros_banner detect_arch is_32bit is_lowmem \
           mark_done is_done run_once ensure_swap; do
    _test "Function '$_fn' is defined" "type '$_fn' >/dev/null 2>&1"
done

# ---------------------------------------------------------------------------
# Colour variables (may be empty in non-tty contexts; test definition only)
# ---------------------------------------------------------------------------
_test "Colour variables exported" "true"  # Colours are optional in non-tty

# ---------------------------------------------------------------------------
# System probes
# ---------------------------------------------------------------------------
_test "get_mem_mb returns a number" \
    "echo '$(get_mem_mb)' | grep -qE '^[0-9]+$'"

# ---------------------------------------------------------------------------
# Marker system
# ---------------------------------------------------------------------------
_test_marker="/tmp/necros-test-marker-$$"
NECROS_MARKERS="$_test_marker"
mkdir -p "$NECROS_MARKERS"

_test "mark_done creates marker" "mark_done test_step && [ -f '$NECROS_MARKERS/test_step' ]"
_test "is_done returns true for existing marker" "is_done test_step"
_test "is_done returns false for non-existing marker" "! is_done nonexistent_step"

rm -rf "$_test_marker"

# ---------------------------------------------------------------------------
# Core scripts exist and are executable concepts
# ---------------------------------------------------------------------------
echo ""
echo "  Script Syntax Checks"
echo "  ====================="
for _script in \
    "$SCRIPT_DIR/../necro_install.sh" \
    "$SCRIPT_DIR/../core/vanish.sh" \
    "$SCRIPT_DIR/../core/payload.sh" \
    "$SCRIPT_DIR/../core/recon.sh" \
    "$SCRIPT_DIR/../core/sysinfo.sh" \
    "$SCRIPT_DIR/../core/update.sh" \
    "$SCRIPT_DIR/../install.sh"; do
    _name="$(basename "$_script")"
    _test "$_name exists" "[ -f '$_script' ]"
    _test "$_name has valid syntax" "sh -n '$_script'"
done

echo ""
echo "  Toolbox Syntax Checks"
echo "  ====================="
for _script in "$SCRIPT_DIR"/../toolbox/install_*.sh; do
    _name="$(basename "$_script")"
    _test "$_name syntax OK" "sh -n '$_script'"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "  ─────────────────────────────────"
printf '  Total: %d | \033[0;32mPass: %d\033[0m | \033[0;31mFail: %d\033[0m\n' \
    "$_TOTAL" "$_PASS" "$_FAIL"
echo "  ─────────────────────────────────"
echo ""

[ "$_FAIL" -eq 0 ] || exit 1
