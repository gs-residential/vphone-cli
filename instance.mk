# ═══════════════════════════════════════════════════════════════════
# instance.mk — Named VM instance management
#
# Usage: make -f instance.mk <target> INSTANCE=<name> [options]
#
# Examples:
#   make -f instance.mk setup  INSTANCE=iphone_01 JB=1
#   make -f instance.mk boot   INSTANCE=iphone_01
#   make -f instance.mk setup  INSTANCE=iphone_02 SKIP_PROJECT_SETUP=1
# ═══════════════════════════════════════════════════════════════════

INSTANCE             ?=
CPU                  ?= 8
MEMORY               ?= 8192
DISK_SIZE            ?= 64
JB                   ?= 0
DEV                  ?= 0
SKIP_PROJECT_SETUP   ?= 0
NONE_INTERACTIVE     ?= 0
SUDO_PASSWORD        ?=

SCRIPTS := scripts

# ─── Guard ────────────────────────────────────────────────────────
_require_instance:
	@test -n "$(INSTANCE)" \
		|| (echo "Error: INSTANCE is required. Example: make -f instance.mk boot INSTANCE=iphone_01" && exit 1)

# ─── Help ─────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo "instance.mk — Named VM instance management"
	@echo ""
	@echo "Usage:"
	@echo "  make -f instance.mk <target> INSTANCE=<name> [options]"
	@echo ""
	@echo "Targets:"
	@echo "  setup        Full machine setup (tools → vm_new → fw → restore → CFW → first boot)"
	@echo "  boot         Boot instance in GUI mode"
	@echo "  boot_dfu     Boot instance in DFU mode"
	@echo "  from_template  Create instance from template via APFS clone (TEMPLATE=<name>)"
	@echo "  clone          Clone instance to a new directory (TARGET=<name>)"
	@echo "  list         List existing instance directories"
	@echo ""
	@echo "Required:"
	@echo "  INSTANCE=    VM directory name (e.g. iphone_01)"
	@echo ""
	@echo "Setup options:"
	@echo "  JB=1                  Jailbreak firmware/CFW"
	@echo "  DEV=1                 Dev firmware/CFW"
	@echo "  SKIP_PROJECT_SETUP=1  Skip setup_tools/build stage"
	@echo "  NONE_INTERACTIVE=1    Auto-continue first-boot prompts + boot analysis"
	@echo "  SUDO_PASSWORD=...     Preload sudo credential"
	@echo ""
	@echo "Boot options:"
	@echo "  CPU=8                 vCPU count"
	@echo "  MEMORY=8192           RAM in MB"
	@echo ""
	@echo "Clone options:"
	@echo "  TARGET=      Destination instance name (required for clone)"
	@echo ""
	@echo "Examples:"
	@echo "  make -f instance.mk setup  INSTANCE=iphone_01 JB=1"
	@echo "  make -f instance.mk boot   INSTANCE=iphone_01"
	@echo "  make -f instance.mk setup  INSTANCE=iphone_02 SKIP_PROJECT_SETUP=1 JB=1"
	@echo "  make -f instance.mk clone  INSTANCE=iphone_01 TARGET=iphone_03"

# ─── Targets ──────────────────────────────────────────────────────
.PHONY: setup
setup: _require_instance
	VM_DIR="$(INSTANCE)" \
	SUDO_PASSWORD="$(SUDO_PASSWORD)" \
	NONE_INTERACTIVE="$(NONE_INTERACTIVE)" \
	zsh $(SCRIPTS)/setup_machine.sh \
		$(if $(filter 1 true yes YES TRUE,$(JB)),--jb,) \
		$(if $(filter 1 true yes YES TRUE,$(DEV)),--dev,) \
		$(if $(filter 1 true yes YES TRUE,$(SKIP_PROJECT_SETUP)),--skip-project-setup,)

.PHONY: boot
boot: _require_instance
	$(MAKE) -f Makefile boot VM_DIR="$(INSTANCE)" CPU="$(CPU)" MEMORY="$(MEMORY)"

.PHONY: boot_dfu
boot_dfu: _require_instance
	$(MAKE) -f Makefile boot_dfu VM_DIR="$(INSTANCE)" CPU="$(CPU)" MEMORY="$(MEMORY)"

TEMPLATE             ?=

.PHONY: from_template
from_template: _require_instance
	@test -n "$(TEMPLATE)" \
		|| (echo "Error: TEMPLATE is required. Example: make -f instance.mk from_template TEMPLATE=iphone_template INSTANCE=iphone_01" && exit 1)
	zsh $(SCRIPTS)/from_template.sh "$(TEMPLATE)" "$(INSTANCE)"

.PHONY: clone
clone: _require_instance
	@test -n "$(TARGET)" \
		|| (echo "Error: TARGET is required. Example: make -f instance.mk clone INSTANCE=iphone_01 TARGET=iphone_03" && exit 1)
	zsh $(SCRIPTS)/clone_instance.sh "$(INSTANCE)" "$(TARGET)"

SSH_PORT             ?= 22222
SSH_USER             ?= root

.PHONY: iproxy_list
iproxy_list:
	zsh $(SCRIPTS)/list_iproxy.sh

.PHONY: iproxy
iproxy: _require_instance
	@UDID=$$(grep '^UDID=' "$(INSTANCE)/udid-prediction.txt" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]') && \
	test -n "$$UDID" || (echo "Error: no udid-prediction.txt in $(INSTANCE)/" && exit 1) && \
	echo "[*] iproxy $(SSH_PORT) -> 22  (instance=$(INSTANCE), udid=$$UDID)" && \
	$(CURDIR)/.limd/bin/iproxy -u "$$UDID" $(SSH_PORT) 22

.PHONY: ssh
ssh: _require_instance
	ssh -p $(SSH_PORT) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@localhost

.PHONY: list
list:
	@echo "Existing instances (directories containing Disk.img):"
	@for d in */; do \
		[ -f "$${d}Disk.img" ] && echo "  $${d%/}" || true; \
	done
