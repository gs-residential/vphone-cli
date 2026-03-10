#!/bin/zsh
# clone_instance.sh — Clone an existing VM instance to a new directory.
#
# Copies all files needed to boot (disk, NVRAM, SEP, identity, ROMs, CFW).
# Skips the large iPhone*_Restore IPSW folder (not needed for booting).
#
# The clone shares the same machineIdentifier (same ECID/UDID) as the source.
# This means:
#   - Both boot fine independently with the same iOS state (apps, settings, data).
#   - You CANNOT run both simultaneously (same disk + same identity = conflict).
#   - If you need simultaneous instances you must do a full setup_instance run.
#
# Usage:
#   zsh scripts/clone_instance.sh <source> <destination>
#
# Examples:
#   zsh scripts/clone_instance.sh iphone_01 iphone_03
#   zsh scripts/clone_instance.sh vm iphone_backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

die()  { echo "[-] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }

usage() {
  cat <<'EOF'
Usage: clone_instance.sh <source> <destination>

  <source>       Existing VM directory (e.g. iphone_01 or vm)
  <destination>  New VM directory to create (e.g. iphone_03)

Both paths are relative to the project root unless absolute.

Notes:
  - The clone has the same ECID/identity as the source (same machineIdentifier.bin).
  - Do NOT run source and clone simultaneously.
  - The large iPhone*_Restore IPSW folder is NOT copied (not needed for booting).
    Copy it manually if you want to be able to re-restore the clone.
EOF
  exit 1
}

# ─── Parse args ──────────────────────────────────────────────────
[[ $# -eq 2 ]] || usage

SRC="$1"
DST="$2"

cd "$PROJECT_ROOT"
[[ "$SRC" == /* ]] || SRC="${PROJECT_ROOT}/${SRC}"
[[ "$DST" == /* ]] || DST="${PROJECT_ROOT}/${DST}"

# ─── Validate source ─────────────────────────────────────────────
[[ -d "$SRC" ]]              || die "Source does not exist: ${SRC}"
[[ -f "${SRC}/Disk.img" ]]   || die "Source missing Disk.img: ${SRC}"
[[ -f "${SRC}/machineIdentifier.bin" ]] || die "Source missing machineIdentifier.bin: ${SRC}"

if command -v lsof >/dev/null 2>&1; then
  local_locks="$(lsof -t -- "${SRC}/Disk.img" "${SRC}/nvram.bin" 2>/dev/null | grep -v "^$$\$" || true)"
  [[ -z "$local_locks" ]] || die "Source VM is running (locked files in ${SRC}). Shut it down first."
fi

# ─── Validate destination ─────────────────────────────────────────
if [[ -d "$DST" ]]; then
  echo "[!] Destination already exists: ${DST}"
  echo -n "[?] Overwrite? [y/N] "
  read -r answer
  [[ "${answer:l}" == "y" ]] || die "Aborted."
  rm -rf "$DST"
fi

# ─── Detect APFS clone support (for small files) ─────────────────
CP_FILE_FLAGS="-a"
CP_DIR_FLAGS="-a"
APFS_CLONE=0

if ! cp --version 2>/dev/null | grep -q GNU; then
  # Test within PROJECT_ROOT — cp -c requires source and destination on the same APFS volume.
  # Testing to /tmp fails because /tmp is a separate volume even on APFS systems.
  # Must use a real regular file — cp -c rejects device files like /dev/null.
  _apfs_src="${PROJECT_ROOT}/.vphone_apfs_src_$$"
  _apfs_dst="${PROJECT_ROOT}/.vphone_apfs_dst_$$"
  touch "$_apfs_src"
  if cp -c "$_apfs_src" "$_apfs_dst" 2>/dev/null; then
    CP_FILE_FLAGS="-ac"
    CP_DIR_FLAGS="-arc"
    APFS_CLONE=1
  fi
  rm -f "$_apfs_src" "$_apfs_dst" 2>/dev/null || true
fi

# ─── Show plan ───────────────────────────────────────────────────
SRC_NAME="${SRC:t}"
DST_NAME="${DST:t}"

DISK_ACTUAL="$(du -sh "${SRC}/Disk.img" 2>/dev/null | cut -f1 || echo "?")"
DISK_BYTES="$(stat -f %z "${SRC}/Disk.img" 2>/dev/null || echo 0)"

echo ""
echo "  Source:      ${SRC_NAME}"
echo "  Destination: ${DST_NAME}"
echo "  Disk.img:    ${DISK_ACTUAL} actual data  ($(( DISK_BYTES / 1024 / 1024 / 1024 ))G logical)"

RESTORE_DIRS=("${SRC}"/iPhone*_Restore(N))
if (( ${#RESTORE_DIRS[@]} > 0 )); then
  RESTORE_SIZE="$(du -sh "${RESTORE_DIRS[1]}" 2>/dev/null | cut -f1 || echo "?")"
  echo "  Skipping:    ${RESTORE_DIRS[1]:t}/ (${RESTORE_SIZE} — not needed for boot)"
fi

if (( APFS_CLONE )); then
  echo "  Method:      APFS copy-on-write clone (fast)"
else
  echo "  Method:      rsync with progress"
fi
echo ""

# ─── Helpers ─────────────────────────────────────────────────────
copy_file() {
  local src_file="$1" dst_file="$2" label="${1:t}"
  [[ -e "$src_file" ]] || return 0
  info "Copying ${label}..."
  cp ${=CP_FILE_FLAGS} "$src_file" "$dst_file"
  ok "  ${label} done"
}

copy_dir() {
  local src_dir="$1" dst_dir="$2" label="${1:t}"
  [[ -d "$src_dir" ]] || return 0
  info "Copying ${label}/..."
  cp ${=CP_DIR_FLAGS} "$src_dir" "$dst_dir"
  ok "  ${label}/ done"
}

# copy_disk — APFS clone (instant) when available, rsync with progress as fallback.
copy_disk() {
  local src_file="$1" dst_file="$2"
  info "Copying Disk.img  (${DISK_ACTUAL} data)..."

  if (( APFS_CLONE )); then
    cp -c "$src_file" "$dst_file" &
    local cp_pid=$!
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
    while kill -0 $cp_pid 2>/dev/null; do
      printf "\r  %s  APFS clone in progress..." "${spin[$(( i % ${#spin[@]} + 1 ))]}"
      sleep 0.1
      (( ++i )) || true
    done
    wait $cp_pid
    printf "\r  %-60s\n" "APFS clone done (copy-on-write, no data transferred)"
  else
    # rsync uses \r for progress — write directly to terminal (no pipe)
    rsync -a --sparse --progress "$src_file" "$dst_file"
    echo ""   # rsync does not always end with a newline
  fi

  ok "  Disk.img done"
}

# ─── Copy ────────────────────────────────────────────────────────
mkdir -p "$DST"

# Disk.img: always use rsync with progress (clear feedback regardless of APFS)
copy_disk "${SRC}/Disk.img" "${DST}/Disk.img"

# Small boot-critical files (APFS clone if available)
copy_file "${SRC}/machineIdentifier.bin"       "${DST}/machineIdentifier.bin"
copy_file "${SRC}/nvram.bin"                   "${DST}/nvram.bin"
copy_file "${SRC}/SEPStorage"                  "${DST}/SEPStorage"
copy_file "${SRC}/AVPBooter.vresearch1.bin"    "${DST}/AVPBooter.vresearch1.bin"
copy_file "${SRC}/AVPSEPBooter.vresearch1.bin" "${DST}/AVPSEPBooter.vresearch1.bin"

# Identity + CFW support files
copy_file "${SRC}/udid-prediction.txt"  "${DST}/udid-prediction.txt"
copy_dir  "${SRC}/shsh"                 "${DST}/shsh"
copy_dir  "${SRC}/cfw_input"            "${DST}/cfw_input"
copy_dir  "${SRC}/cfw_jb_input"         "${DST}/cfw_jb_input"
copy_dir  "${SRC}/Ramdisk"              "${DST}/Ramdisk"
copy_dir  "${SRC}/ramdisk_input"        "${DST}/ramdisk_input"

# Anything else at root (skip restore folder, logs, setup_logs)
for f in "${SRC}"/*; do
  fname="${f:t}"
  [[ -e "${DST}/${fname}" ]] && continue
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
ok "Clone complete: ${DST_NAME}"
echo ""
echo "  To boot the clone:"
echo "    make boot VM_DIR=${DST_NAME}"
echo "    make -f instance.mk boot INSTANCE=${DST_NAME}"
echo ""
echo "  [!] Same ECID as ${SRC_NAME} — do NOT run both at the same time."
echo "      Same apps, settings, and data as at the time of cloning."
