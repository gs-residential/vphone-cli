#!/bin/zsh
# setup_instance.sh — Named instance wrapper for setup_machine.sh.
#
# Sets VM_DIR to <instance-name> and delegates everything to setup_machine.sh.
# The exported VM_DIR propagates through all sub-make calls inside setup_machine.sh
# (vm_new, boot_dfu, restore, ramdisk_build, ramdisk_send, cfw_install, boot).
#
# Usage:
#   zsh setup_instance.sh <instance-name> [--jb] [--dev] [--skip-project-setup]
#
# Examples:
#   zsh scripts/setup_instance.sh iphone_01 --jb
#   zsh scripts/setup_instance.sh iphone_02
#   NONE_INTERACTIVE=1 SUDO_PASSWORD=mypass zsh scripts/setup_instance.sh iphone_01 --jb

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage: setup_instance.sh <instance-name> [--jb] [--dev] [--skip-project-setup]

Arguments:
  <instance-name>         VM directory name (e.g. iphone_01, iphone_02)
                          Directory is created relative to the project root.

Options passed to setup_machine.sh:
  --jb                    Jailbreak firmware/CFW path
  --dev                   Dev firmware/CFW path
  --skip-project-setup    Skip setup_tools/build stage

Environment (same as setup_machine.sh):
  NONE_INTERACTIVE=1      Auto-continue first-boot prompts + boot analysis
  SUDO_PASSWORD=...       Preload sudo credential for setup flow
EOF
  exit 1
}

if [[ $# -lt 1 ]] || [[ "$1" == -h ]] || [[ "$1" == --help ]]; then
  usage
fi

if [[ "$1" == --* ]]; then
  echo "[-] First argument must be the instance name, not a flag." >&2
  usage
fi

INSTANCE="$1"
shift

export VM_DIR="$INSTANCE"

echo "[*] Instance: ${INSTANCE}  (VM_DIR=${VM_DIR})"
exec zsh "${SCRIPT_DIR}/setup_machine.sh" "$@"
