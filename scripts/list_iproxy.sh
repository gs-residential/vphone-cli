#!/bin/zsh
# list_iproxy.sh — Show running iproxy tunnels and match them to VM instances.
#
# Usage:
#   zsh scripts/list_iproxy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Build UDID → instance name map from udid-prediction.txt files ───
typeset -A UDID_TO_INSTANCE
for f in "${PROJECT_ROOT}"/*/udid-prediction.txt(N); do
  instance="${f:h:t}"
  udid="$(grep '^UDID=' "$f" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')"
  [[ -n "$udid" ]] && UDID_TO_INSTANCE["${udid:u}"]="$instance"
done

# ─── Parse running iproxy processes ──────────────────────────────────
# iproxy is called as: iproxy [-u UDID] LOCAL_PORT REMOTE_PORT
iproxy_procs="$(ps -eo pid,command | grep '[i]proxy' || true)"

if [[ -z "$iproxy_procs" ]]; then
  echo "No iproxy processes running."
  exit 0
fi

echo ""
printf "  %-8s  %-6s  %-6s  %-40s  %s\n" "PID" "LOCAL" "REMOTE" "UDID" "INSTANCE"
printf "  %-8s  %-6s  %-6s  %-40s  %s\n" "--------" "------" "------" "----------------------------------------" "--------"

echo "$iproxy_procs" | while read -r pid cmd; do
  # Extract -u UDID if present
  udid=""
  local_port=""
  remote_port=""

  args=("${(z)cmd}")   # split into words
  i=1
  while (( i <= ${#args} )); do
    case "${args[$i]}" in
      -u)
        (( i++ ))
        udid="${args[$i]:u}"
        ;;
      [0-9]*)
        if [[ -z "$local_port" ]]; then
          local_port="${args[$i]}"
        else
          remote_port="${args[$i]}"
        fi
        ;;
    esac
    (( ++i )) || true
  done

  instance="${UDID_TO_INSTANCE[$udid]:-unknown}"

  printf "  %-8s  %-6s  %-6s  %-40s  %s\n" \
    "$pid" "${local_port:--}" "${remote_port:--}" "${udid:-(no -u flag)}" "$instance"
done

echo ""
echo "  SSH:  ssh -p <LOCAL> root@localhost"
echo ""
