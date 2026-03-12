# Changelog

All notable changes to NecrOS will be documented in this file.

## [1.0.0] — 2026-03-09

### Architecture
- **Shared library** (`lib/necros-common.sh`): single source of truth for colours, logging, architecture detection, package helpers, swap management, idempotent marker system
- **Idempotent installer**: every step uses `run_once` markers — safe to re-run after failure
- **Automatic swap**: machines with <512MB RAM get automatic swap file creation
- **Auto-downgrade**: machines with <384MB RAM automatically switch to `--minimal` mode
- **Alpine version auto-detection**: no more hardcoded repository URLs

### New Core Tools
- `necros-recon`: automated reconnaissance pipeline (DNS, WHOIS, port scan, web recon, passive OSINT, report generation)
- `necros-sysinfo`: system information dashboard (hardware, network, installed tools, toolbox status)
- `necros-update`: self-updater (check, pull, system update)
- `necros-crypt`: crypto swiss army knife (hash, encode, encrypt, generate passwords)

### Improved Core Tools
- `necros-vanish` v2.0: better POSIX compliance, NecrOS trace cleanup, expanded wipe targets
- `necros-payload` v2.0: 13 reverse shells (added OpenSSL encrypted), MSFvenom templates, shell upgrade section, CLI quick mode with `--lhost`/`--lport` flags

### New Toolboxes
- **OSINT & Recon**: subdomain enumeration (crt.sh, subfinder), WHOIS, Shodan CLI, exiftool, theHarvester
- **Crypto & Stego**: steghide, pycryptodome, `necros-crypt` multi-tool, hash identification

### Improved Toolboxes
- All toolboxes now use the shared library (no more duplicated code)
- Architecture-aware installation throughout (32-bit light mode)
- Toolbox status tracking via marker system

### Build System
- `Makefile` with lint, test, build, release targets
- `build_iso.sh` rewritten with proper Alpine mkimage integration + fallback
- `install.sh` rewritten for network install with git/wget/curl fallback chain

### Quality
- Full test suite (`tests/test_lib.sh`): library functions, syntax validation, markers
- GitHub Actions CI: shellcheck lint, syntax check, tests on Ubuntu + Alpine container
- All scripts pass `sh -n` syntax validation
- shellcheck compliance (SC1091, SC2034, SC1008 excluded by design)

### Project Infrastructure
- `VERSION` file (single source of truth)
- `LICENSE` (MIT)
- `CHANGELOG.md`
- `CONTRIBUTING.md`
- Comprehensive `.gitignore`

---

## [0.3.0] — 2024 (Previous)

- necros-vanish: ghost/stealth/nuclear modes
- necros-payload: 12+ reverse shells
- Boot splash animation
- Blue Team toolbox

## [0.2.0] — 2024 (Initial)

- Base Alpine Linux installer
- i3wm + urxvt theme
- WiFi, Web, Reverse Engineering toolboxes
- Zsh + Oh My Zsh configuration
