#!/usr/bin/env bash
# Adapted r8s BOOT flash script (dry-run by default; requires --write).
# Fixes GNU/Linux stat/sha256sum portability, single-device ADB selection,
# missing stock backup handling, and mandatory pre-write backup verification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=adb-common.sh
. "$SCRIPT_DIR/adb-common.sh"

ROOT="${R8S_WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BK="${R8S_BACKUPS_DIR:-$ROOT/backups}"
IMG=""
DO_WRITE=0

for a in "$@"; do
  case "$a" in
    --write) DO_WRITE=1 ;;
    -*) echo "unknown option: $a" >&2; exit 2 ;;
    *) IMG="$a" ;;
  esac
done

[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "usage: flash-boot.sh <image> [--write]" >&2; exit 2; }

adb_require_single_root_device

read -r dev sectors part_bytes < <(resolve_partition_info "boot")
img_bytes=$(host_file_size "$IMG")
img_hash=$(host_sha256 "$IMG")
batt=$(adb_cmd shell 'cat /sys/class/power_supply/battery/capacity' | tr -d '\r')

echo "=============================================================="
echo " serial    : $ANDROID_SERIAL"
echo " target    : boot -> $dev ($sectors sectors, $part_bytes bytes)"
echo " image     : $IMG"
echo " size      : $img_bytes bytes ($(awk -v a="$img_bytes" -v b="$part_bytes" 'BEGIN{printf "%.1f", a*100/b}')% of partition)"
echo " sha256    : $img_hash"
echo " battery   : ${batt}%"

[ "$img_bytes" -le "$part_bytes" ] || { echo " ABORT: image larger than partition." >&2; exit 7; }
[ "${batt:-0}" -ge 20 ] || { echo " ABORT: battery below 20%." >&2; exit 8; }

stock_boot="$BK/stock-boot.img"
verify_file="$BK/stock-backup-verify.txt"
[ -f "$stock_boot" ] || { echo " ABORT: missing stock backup: $stock_boot" >&2; exit 6; }
[ -f "$verify_file" ] || { echo " ABORT: missing backup hash manifest: $verify_file" >&2; exit 6; }

want_stock=$(awk '$1=="boot" {print $2}' "$verify_file" | head -n 1)
want_stock=${want_stock#device=}
[ -n "$want_stock" ] || { echo " ABORT: missing recorded 'boot' hash in $verify_file" >&2; exit 8; }
have_stock=$(host_sha256 "$stock_boot")
[ "$have_stock" = "$want_stock" ] || {
  echo " ABORT: stock-boot.img hash mismatch (expected $want_stock, got $have_stock)" >&2
  exit 8
}

live_pre=$(adb_cmd shell "dd if=$dev bs=512 count=$sectors 2>/dev/null | sha256sum" | awk '{print $1}')
echo " live boot : $live_pre (before)"
if [ "$live_pre" = "$have_stock" ]; then
  echo " note      : current boot == verified stock backup, restore is available"
else
  ts=$(date +%Y%m%d-%H%M%S)
  echo " note      : current boot differs from stock; snapshotting to $BK/pre-flash-$ts.img"
  if [ "$DO_WRITE" = "1" ]; then
    mkdir -p "$BK"
    adb_cmd exec-out "dd if=$dev bs=512 count=$sectors 2>/dev/null" > "$BK/pre-flash-$ts.img"
    snap_hash=$(host_sha256 "$BK/pre-flash-$ts.img")
    [ "$snap_hash" = "$live_pre" ] || {
      echo " ABORT: pre-flash snapshot hash mismatch (expected $live_pre, got $snap_hash)" >&2
      exit 6
    }
  fi
fi

if [ "$DO_WRITE" != "1" ]; then
  echo " DRY RUN - nothing written. Re-run with --write."
  exit 0
fi

echo " WRITING..."
adb_cmd push "$IMG" /data/local/tmp/flash-boot.img >/dev/null
adb_cmd shell "dd if=/dev/zero of=$dev bs=1M count=$((part_bytes/1048576)) conv=fsync 2>/dev/null; \
               dd if=/data/local/tmp/flash-boot.img of=$dev bs=1M conv=fsync && sync && echo 3 > /proc/sys/vm/drop_caches"
back=$(adb_cmd shell "dd if=$dev bs=1 count=$img_bytes 2>/dev/null | sha256sum" | awk '{print $1}')
adb_cmd shell "rm -f /data/local/tmp/flash-boot.img"
if [ "$back" = "$img_hash" ]; then
  echo " VERIFIED: first $img_bytes bytes of $dev match the image. Flash OK."
else
  echo " *** READBACK MISMATCH - DO NOT REBOOT. Run restore-stock.sh --write boot ***" >&2
  echo "   expected $img_hash" >&2
  echo "   got      $back" >&2
  exit 9
fi
