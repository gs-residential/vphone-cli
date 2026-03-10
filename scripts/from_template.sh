#!/bin/zsh
# from_template.sh — Create a new VM instance from a template using APFS clone.
#
# The disk image is NOT copied. On APFS, cp -c creates a copy-on-write clone:
#   - Completes in ~1 second regardless of disk size.
#   - Uses zero extra disk space until the instance actually writes new data.
#   - Each instance is fully independent — writes do not affect the template.
#
# Workflow:
#   1. Set up template once:  make -f instance.mk setup INSTANCE=iphone_template JB=1
#   2. Spin up instances:     make -f instance.mk from_template TEMPLATE=iphone_template INSTANCE=iphone_01
#   3. Boot:                  make -f instance.mk boot INSTANCE=iphone_01
#
# Usage:
#   zsh scripts/from_template.sh <template-dir> <new-instance-dir>
#
# Examples:
#   zsh scripts/from_template.sh iphone_template iphone_01
#   zsh scripts/from_template.sh iphone_template iphone_02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

die()  { echo "[-] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }

usage() {
  cat <<'EOF'
Usage: from_template.sh <template> <instance>

  <template>   Template VM directory (e.g. iphone_template)
  <instance>   New instance directory to create (e.g. iphone_01)

Both paths are relative to the project root unless absolute.

The template disk is NOT copied — APFS copy-on-write shares blocks until the
instance writes new data. Each instance is fully independent after creation.

Note: All instances created from the same template share the same ECID
(stored in config.plist). Do NOT run more than one at the same time.
EOF
  exit 1
}

# ─── Parse args ──────────────────────────────────────────────────
[[ $# -eq 2 ]] || usage

TMPL="$1"
DST="$2"

cd "$PROJECT_ROOT"
[[ "$TMPL" == /* ]] || TMPL="${PROJECT_ROOT}/${TMPL}"
[[ "$DST"  == /* ]] || DST="${PROJECT_ROOT}/${DST}"

# ─── Validate template ───────────────────────────────────────────
[[ -d "$TMPL" ]]              || die "Template does not exist: ${TMPL}"
[[ -f "${TMPL}/Disk.img" ]]   || die "Template missing Disk.img: ${TMPL}"
[[ -f "${TMPL}/config.plist" ]] || die "Template missing config.plist: ${TMPL}"

# ─── Validate destination ─────────────────────────────────────────
if [[ -d "$DST" ]]; then
  echo "[!] Destination already exists: ${DST}"
  echo -n "[?] Overwrite? [y/N] "
  read -r answer
  [[ "${answer:l}" == "y" ]] || die "Aborted."
  rm -rf "$DST"
fi

# ─── Detect APFS clone support ───────────────────────────────────
APFS_CLONE=0
if ! cp --version 2>/dev/null | grep -q GNU; then
  # Test within PROJECT_ROOT — cp -c requires same APFS volume.
  # /tmp is a separate volume so testing there always fails.
  # Must use a real regular file — cp -c rejects device files like /dev/null.
  _apfs_src="${PROJECT_ROOT}/.vphone_apfs_src_$$"
  _apfs_dst="${PROJECT_ROOT}/.vphone_apfs_dst_$$"
  touch "$_apfs_src"
  if cp -c "$_apfs_src" "$_apfs_dst" 2>/dev/null; then
    APFS_CLONE=1
  fi
  rm -f "$_apfs_src" "$_apfs_dst" 2>/dev/null || true
fi

TMPL_NAME="${TMPL:t}"
DST_NAME="${DST:t}"
DISK_ACTUAL="$(du -sh "${TMPL}/Disk.img" 2>/dev/null | cut -f1 || echo "?")"
DISK_LOGICAL=$(( $(stat -f %z "${TMPL}/Disk.img" 2>/dev/null || echo 0) / 1024 / 1024 / 1024 ))

echo ""
echo "  Template:    ${TMPL_NAME}"
echo "  Instance:    ${DST_NAME}"
echo "  Disk.img:    ${DISK_ACTUAL} data  (${DISK_LOGICAL}G logical)"
if (( APFS_CLONE )); then
  echo "  Method:      APFS copy-on-write  (instant, zero extra space until first write)"
else
  echo "  Method:      rsync --sparse  (APFS not available, full copy with progress)"
fi
echo ""

# ─── Create instance directory ───────────────────────────────────
mkdir -p "$DST"

# ─── Clone disk ──────────────────────────────────────────────────
info "Cloning Disk.img..."

if (( APFS_CLONE )); then
  # Instant copy-on-write — the OS shares APFS extents, no data is read/written.
  # A spinner gives feedback since it takes ~1-2 seconds for a large sparse file.
  cp -c "${TMPL}/Disk.img" "${DST}/Disk.img" &
  CP_PID=$!
  SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  i=0
  while kill -0 $CP_PID 2>/dev/null; do
    printf "\r  %s  APFS clone in progress..." "${SPIN[$(( i % ${#SPIN[@]} + 1 ))]}"
    sleep 0.1
    (( ++i )) || true
  done
  wait $CP_PID
  printf "\r  ✓  Disk.img cloned (copy-on-write, no data transferred)        \n"
else
  # Fallback: rsync written directly to terminal so \r progress updates are visible
  rsync -a --sparse --progress "${TMPL}/Disk.img" "${DST}/Disk.img"
  echo ""   # rsync does not always end with a newline
fi

ok "  Disk.img ready"

# ─── Copy remaining files ─────────────────────────────────────────
copy_file() {
  local src="$1" dst="$2"
  [[ -e "$src" ]] || return 0
  cp -a "$src" "$dst"
  ok "  ${src:t} copied"
}

copy_dir() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  cp -a "$src" "$dst"
  ok "  ${src:t}/ copied"
}

info "Copying remaining files..."

copy_file "${TMPL}/nvram.bin"                   "${DST}/nvram.bin"
copy_file "${TMPL}/SEPStorage"                  "${DST}/SEPStorage"
copy_file "${TMPL}/AVPBooter.vresearch1.bin"    "${DST}/AVPBooter.vresearch1.bin"
copy_file "${TMPL}/AVPSEPBooter.vresearch1.bin" "${DST}/AVPSEPBooter.vresearch1.bin"
copy_file "${TMPL}/udid-prediction.txt"         "${DST}/udid-prediction.txt"
copy_dir  "${TMPL}/shsh"                        "${DST}/shsh"
copy_dir  "${TMPL}/cfw_input"                   "${DST}/cfw_input"
copy_dir  "${TMPL}/cfw_jb_input"                "${DST}/cfw_jb_input"
copy_dir  "${TMPL}/Ramdisk"                     "${DST}/Ramdisk"
copy_dir  "${TMPL}/ramdisk_input"               "${DST}/ramdisk_input"

# Anything else at root (skip restore folder, logs)
for f in "${TMPL}"/*; do
  fname="${f:t}"
  [[ -e "${DST}/${fname}" ]]     && continue
  [[ "$fname" == iPhone*_Restore ]] && continue
  [[ "$fname" == *.log ]]           && continue
  [[ "$fname" == setup_logs ]]      && continue
  if [[ -f "$f" ]]; then
    copy_file "$f" "${DST}/${fname}"
  elif [[ -d "$f" ]]; then
    copy_dir "$f" "${DST}/${fname}"
  fi
done

# ─── Summary ─────────────────────────────────────────────────────
echo ""
ok "Instance ready: ${DST_NAME}"
echo ""
echo "  To boot:"
echo "    make boot VM_DIR=${DST_NAME}"
echo "    make -f instance.mk boot INSTANCE=${DST_NAME}"
echo ""
echo "  [!] Same machineIdentifier/ECID as ${TMPL_NAME} — do NOT run multiple instances simultaneously."
echo "      Each instance disk is independent from this point (writes are isolated)."
