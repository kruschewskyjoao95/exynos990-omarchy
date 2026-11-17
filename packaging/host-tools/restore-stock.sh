#!/usr/bin/env bash
# Adapted r8s stock partition restore script (dry-run by default; requires --write).
# Fixes GNU/Linux stat/sha256sum portability, single-device ADB selection, and
# makes missing/empty backup hash manifest a hard failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=adb-common.sh
. "$SCRIPT_DIR/adb-common.sh"

ROOT="${R8S_WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BK="${R8S_BACKUPS_DIR:-$ROOT/backups}"
ALLOWED="boot recovery dtbo"

DO_WRITE=0
TARGETS=""
for a in "$@"; do
  case "$a" in
    --write) DO_WRITE=1 ;;
    -*) echo "unknown option: $a" >&2; exit 2 ;;
    *) TARGETS="$TARGETS $a" ;;
  esac
done
[ -n "${TARGETS// /}" ] || TARGETS="$ALLOWED"

for p in $TARGETS; do
  case " $ALLOWED " in
    *" $p "*) ;;
    *) echo "REFUSING: '$p' is not in the allow-list ($ALLOWED)" >&2; exit 3 ;;
  esac
done

adb_require_single_root_device

verify_file="$BK/stock-backup-verify.txt"
[ -f "$verify_file" ] || { echo "missing backup hash manifest: $verify_file" >&2; exit 8; }

for p in $TARGETS; do
  img="$BK/stock-$p.img"
  [ -f "$img" ] || { echo "missing backup: $img" >&2; exit 6; }

  read -r dev sectors bytes < <(resolve_partition_info "$p")
  local_bytes=$(host_file_size "$img")

  echo "=============================================================="
  echo " serial    : $ANDROID_SERIAL"
  echo " partition : $p  ->  $dev  ($sectors sectors, $bytes bytes)"
  echo " image     : $img ($local_bytes bytes)"

  if [ "$local_bytes" != "$bytes" ]; then
    echo " ABORT: image size does not match partition size." >&2
    exit 7
  fi

  want=$(awk -v k="$p" '$1==k {print $2}' "$verify_file" | head -n 1)
  want=${want#device=}
  if [ -z "$want" ]; then
    echo " ABORT: missing recorded hash for '$p' in $verify_file." >&2
    exit 8
  fi
  have=$(host_sha256 "$img")
  if [ "$want" != "$have" ]; then
    echo " ABORT: local image does not match its recorded hash." >&2
    exit 8
  fi
  echo " sha256    : $have (image verified)"

  if [ "$DO_WRITE" != "1" ]; then
    echo " DRY RUN - nothing written. Re-run with --write to restore."
    continue
  fi

  echo " WRITING..."
  adb_cmd push "$img" "/data/local/tmp/restore-$p.img" >/dev/null
  adb_cmd shell "dd if=/data/local/tmp/restore-$p.img of=$dev bs=1M conv=fsync && sync && echo 3 > /proc/sys/vm/drop_caches"
  back=$(adb_cmd shell "dd if=$dev bs=512 count=$sectors 2>/dev/null | sha256sum" | awk '{print $1}')
  adb_cmd shell "rm -f /data/local/tmp/restore-$p.img"
  if [ "$back" = "$have" ]; then
    echo " VERIFIED: readback matches. $p restored."
  else
    echo " *** READBACK MISMATCH on $p - DO NOT REBOOT. ***" >&2
    echo "   expected $have" >&2
    echo "   got      $back" >&2
    exit 9
  fi
done
