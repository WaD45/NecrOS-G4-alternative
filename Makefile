# ============================================================================
#  NecrOS Makefile
# ============================================================================

VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.0")
SHELL   := /bin/sh
SCRIPTS := $(shell find . -name '*.sh' -not -path './.git/*')

.PHONY: help lint test build clean install

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Run shellcheck on all scripts
	@echo "[*] Running shellcheck on $(words $(SCRIPTS)) scripts..."
	@_fail=0; for f in $(SCRIPTS); do \
		shellcheck -s sh -e SC1091,SC2034,SC1008 "$$f" || _fail=1; \
	done; \
	if [ "$$_fail" -eq 0 ]; then echo "[✓] All scripts passed shellcheck"; \
	else echo "[!] Some scripts have warnings"; fi

test: lint ## Run lint + integration tests
	@echo "[*] Running tests..."
	@sh tests/test_lib.sh
	@echo "[✓] All tests passed"

build: ## Build the ISO (requires Alpine Linux)
	@echo "[*] Building NecrOS v$(VERSION) ISO..."
	@sh build_iso.sh --arch x86 --output build/
	@echo "[✓] Build complete"

build-64: ## Build 64-bit ISO
	@sh build_iso.sh --arch x86_64 --output build/

clean: ## Clean build artifacts
	@rm -rf build/ /tmp/necros-*
	@echo "[✓] Cleaned"

install: ## Install NecrOS on current Alpine system (requires root)
	@sh necro_install.sh

release: lint test ## Create a release tarball
	@mkdir -p build
	@tar czf "build/necros-$(VERSION).tar.gz" \
		--exclude='.git' --exclude='build' --exclude='*.tar.gz' \
		-C .. "$(notdir $(CURDIR))"
	@echo "[✓] Release tarball: build/necros-$(VERSION).tar.gz"

version: ## Show current version
	@echo "NecrOS v$(VERSION)"
