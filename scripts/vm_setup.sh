#!/bin/zsh
# vm_setup.sh — Create and fully provision a named vphone VM in one step.
#
# Wraps setup_machine.sh with a required VM name argument.
#
# Usage:
#   ./scripts/vm_setup.sh iPhone_01
#   ./scripts/vm_setup.sh iPhone_01 --jb
#   ./scripts/vm_setup.sh iPhone_01 --dev
#   ./scripts/vm_setup.sh iPhone_01 --skip-project-setup
#
# All extra arguments are forwarded to setup_machine.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Require VM name as first positional argument ---
if [[ $# -eq 0 || "$1" == -* ]]; then
    echo "Usage: $0 <vm-name> [--jb] [--dev] [--skip-project-setup]"
    echo ""
    echo "  vm-name   Directory name for the new VM (e.g. iPhone_01)"
    echo ""
    echo "  --jb                  Jailbreak firmware + CFW"
    echo "  --dev                 Dev firmware + CFW"
    echo "  --skip-project-setup  Skip setup_tools/build stage"
    exit 1
fi

VM_NAME="$1"
shift

export VM_DIR="$VM_NAME"

echo "=== vm_setup: creating VM '${VM_NAME}' ==="
exec "${SCRIPT_DIR}/setup_machine.sh" "$@"
