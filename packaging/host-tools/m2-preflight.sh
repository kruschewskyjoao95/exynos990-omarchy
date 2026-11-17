#!/usr/bin/env bash
# Read-only M2 host preflight check for SM-G780F / r8s.
# Verifies host flashing/recovery tools, out/ & blobs/ SHA-256 checksums,
# and stock firmware/backup integrity without writing anything to any device.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=adb-common.sh
. "$SCRIPT_DIR/adb-common.sh"

ROOT="${R8S_WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STOCK_DIR="${R8S_STOCK_DIR:-$HOME/Downloads/s20fe-stock/extracted}"
BACKUPS_DIR="${R8S_BACKUPS_DIR:-$ROOT/backups}"
SAMLOADER_BIN="${R8S_SAMLOADER_BIN:-}"
SERIAL_TOOL="${R8S_SERIAL_TOOL:-$ROOT/sources/port/tools/r8s-serial.py}"

PROBE_DEVICE=0
STRICT_BACKUPS=0
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

usage() {
  cat <<'EOF'
usage: m2-preflight.sh [--probe-device] [--strict-backups] [--help]

Read-only M2 preflight verification (never writes or flashes any device):
  --probe-device    Also run read-only adb/fastboot/heimdall device discovery
  --strict-backups  Fail if R8S_BACKUPS_DIR lacks verified live partition backups
  --help            Show this message and exit
EOF
}

for arg in "$@"; do
  case "$arg" in
    --probe-device) PROBE_DEVICE=1 ;;
    --strict-backups) STRICT_BACKUPS=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS [%s] %s\n' "$1" "$2"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf 'WARN [%s] %s\n' "$1" "$2"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL [%s] %s\n' "$1" "$2" >&2
}

verify_sha_manifest_entry() {
  local label=$1 file=$2 sha_file=$3
  if [ ! -f "$file" ] || [ ! -f "$sha_file" ]; then
    fail "$label" "missing $file or $sha_file"
    return
  fi
  local base want have
  base=$(basename "$file")
  want=$(awk -v b="$base" '$2 ~ ("(^|/)" b "$") {print $1; exit}' "$sha_file")
  if [ -z "$want" ]; then
    fail "$label" "missing entry for $base in $sha_file"
    return
  fi
  have=$(host_sha256 "$file")
  if [ "$have" = "$want" ]; then
    pass "$label" "$base ($(host_file_size "$file") bytes, sha256=$have)"
  else
    fail "$label" "sha256 mismatch for $base (expected $want, got $have)"
  fi
}

verify_exact_sha() {
  local label=$1 file=$2 want=$3
  if [ ! -f "$file" ]; then
    fail "$label" "missing $file"
    return
  fi
  local have
  have=$(host_sha256 "$file")
  if [ "$have" = "$want" ]; then
    pass "$label" "$(basename "$file") ($(host_file_size "$file") bytes, sha256=$have)"
  else
    fail "$label" "sha256 mismatch for $file (expected $want, got $have)"
  fi
}

echo "== 1. Host tools (read-only check) =="

if command -v heimdall >/dev/null 2>&1; then
  pass "tool-heimdall" "$(command -v heimdall) ($(heimdall version 2>&1 | head -n1))"
else
  fail "tool-heimdall" "heimdall not found in PATH"
fi

if command -v fastboot >/dev/null 2>&1; then
  pass "tool-fastboot" "$(command -v fastboot) ($(fastboot --version 2>&1 | head -n1))"
else
  fail "tool-fastboot" "fastboot not found in PATH"
fi

if command -v adb >/dev/null 2>&1; then
  pass "tool-adb" "$(command -v adb) ($(adb --version 2>&1 | head -n1))"
else
  fail "tool-adb" "adb not found in PATH"
fi

if [ -z "$SAMLOADER_BIN" ]; then
  if command -v samloader >/dev/null 2>&1; then
    SAMLOADER_BIN=$(command -v samloader)
  elif [ -x "$HOME/Downloads/s20fe-lineageos/samloader" ]; then
    SAMLOADER_BIN="$HOME/Downloads/s20fe-lineageos/samloader"
  fi
fi

if [ -n "$SAMLOADER_BIN" ] && [ -x "$SAMLOADER_BIN" ]; then
  sam_ver=$("$SAMLOADER_BIN" --version 2>&1 | head -n1 || echo "version-unknown")
  pass "tool-samloader" "$SAMLOADER_BIN ($sam_ver)"
else
  warn "tool-samloader" "samloader not found in PATH or ~/Downloads/s20fe-lineageos/samloader (optional once stock zip is cached)"
fi

if [ -f "$SERIAL_TOOL" ]; then
  if python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$SERIAL_TOOL" 2>/dev/null; then
    if grep -q '/dev/cu\.usbmodem' "$SERIAL_TOOL"; then
      warn "tool-r8s-serial" "$SERIAL_TOOL syntax ok, but hardcodes macOS /dev/cu.usbmodem* (on Linux USB ACM uses /dev/ttyACM*)"
    else
      pass "tool-r8s-serial" "$SERIAL_TOOL syntax ok"
    fi
  else
    fail "tool-r8s-serial" "$SERIAL_TOOL failed Python syntax parse"
  fi
else
  fail "tool-r8s-serial" "missing $SERIAL_TOOL"
fi

echo "== 2. Verifying out/ artifacts, size budgets, and blobs/ SHA-256s =="

if [ -f "$ROOT/out/boot/kernel-release.txt" ]; then
  # shellcheck source=/dev/null
  . "$ROOT/out/boot/kernel-release.txt"
  pass "kernel-release" "kernelrelease=${kernelrelease:-}"
else
  kernelrelease=""
  fail "kernel-release" "missing $ROOT/out/boot/kernel-release.txt"
fi

verify_sha_manifest_entry "out-lk3rd-img" "$ROOT/out/boot/lk3rd-r8s.img" "$ROOT/out/boot/lk3rd-r8s.sha256"
verify_sha_manifest_entry "out-lk3rd-tar" "$ROOT/out/boot/lk3rd-r8s.tar" "$ROOT/out/boot/lk3rd-r8s.sha256"
verify_sha_manifest_entry "out-kernel-Image" "$ROOT/out/boot/Image" "$ROOT/out/boot/kernel.sha256"
verify_sha_manifest_entry "out-kernel-dtb" "$ROOT/out/boot/exynos990-r8s.dtb" "$ROOT/out/boot/kernel.sha256"
[ -n "${kernelrelease:-}" ] && verify_sha_manifest_entry "out-modules" "$ROOT/out/modules-$kernelrelease.tar.gz" "$ROOT/out/boot/kernel.sha256"
verify_sha_manifest_entry "out-initramfs-slim" "$ROOT/out/boot/initramfs-slim.cpio.gz" "$ROOT/out/boot/initramfs-slim.sha256"
verify_sha_manifest_entry "out-initramfs-mini" "$ROOT/out/boot/initramfs-mini.cpio.gz" "$ROOT/out/boot/initramfs-mini.sha256"
verify_sha_manifest_entry "out-r8s-ram" "$ROOT/out/boot/r8s-ram.img" "$ROOT/out/boot/r8s-ram.sha256"
verify_sha_manifest_entry "out-r8s-mini" "$ROOT/out/boot/r8s-mini.img" "$ROOT/out/boot/r8s-mini.sha256"
verify_sha_manifest_entry "out-r8s-ufs" "$ROOT/out/boot/r8s-ufs.img" "$ROOT/out/boot/r8s-ufs.sha256"
verify_sha_manifest_entry "out-ufs-root" "$ROOT/out/rootfs/ufs-root.img" "$ROOT/out/rootfs/ufs-root.sha256"

for ram_img in "$ROOT/out/boot/r8s-ram.img" "$ROOT/out/boot/r8s-mini.img"; do
  if [ -f "$ram_img" ]; then
    ram_label=$(basename "$ram_img" .img)
    ram_bytes=$(host_file_size "$ram_img")
    [ "$ram_bytes" -le 67108864 ] \
      && pass "budget-$ram_label" "$ram_bytes <= 67108864 bytes (lk3rd 64 MiB buffer)" \
      || fail "budget-$ram_label" "$ram_bytes > 67108864 bytes"
  fi
done

if [ -f "$ROOT/out/rootfs/ufs-root.img" ]; then
  ufs_bytes=$(host_file_size "$ROOT/out/rootfs/ufs-root.img")
  [ "$ufs_bytes" -le 734003200 ] \
    && pass "budget-ufs-root" "$ufs_bytes <= 734003200 bytes (700 MiB < 768 MiB lk3rd buffer)" \
    || fail "budget-ufs-root" "$ufs_bytes > 734003200 bytes"
fi

verify_exact_sha "blob-slk-stock-dtb" "$ROOT/blobs/slk-stock.dtb" "30c5769030bd4f801791c7888f8eb57ebc9e8fd944b88972800219d0355ab3f1"
verify_exact_sha "blob-qca-amss" "$ROOT/blobs/firmware/ath11k/QCA6390/hw2.0/amss.bin" "8ab2a06422e3989012df423bb6a156fde2c3feb4cd5db4c5d3588f674dc872ff"
verify_exact_sha "blob-qca-m3" "$ROOT/blobs/firmware/ath11k/QCA6390/hw2.0/m3.bin" "1921d25edb52f90a7a0acc7275861e14399f904d579aae9f7ab1c4d28533fad6"
verify_exact_sha "blob-qca-board2" "$ROOT/blobs/firmware/ath11k/QCA6390/hw2.0/board-2.bin" "4aa9f0fe15e9e2b6f9bb13b7187ed8ce035d9d46fb65fac5d5eba2c4e7edc091"

echo "== 3. Verifying stock firmware & partition backups (read-only) =="

if [ -d "$STOCK_DIR" ] && [ -f "$STOCK_DIR/stock-hashes.sha256" ]; then
  while read -r want name; do
    [ -n "${want:-}" ] && [ -n "${name:-}" ] || continue
    verify_exact_sha "stock-$name" "$STOCK_DIR/$name" "$want"
  done < "$STOCK_DIR/stock-hashes.sha256"
  verify_exact_sha "stock-boot-pin" "$STOCK_DIR/boot.img" "b33380a1aaf6be060bf2daad042b5c9c820105f3e3f03059c08d4551508a6487"
else
  msg="stock extracted dir/manifest not found at $STOCK_DIR (set R8S_STOCK_DIR)"
  if [ "$STRICT_BACKUPS" -eq 1 ]; then
    fail "stock-dir" "$msg"
  else
    warn "stock-dir" "$msg"
  fi
fi

if [ -f "$BACKUPS_DIR/stock-backup-verify.txt" ]; then
  for part in boot recovery dtbo; do
    want=$(awk -v k="$part" '$1==k {print $2; exit}' "$BACKUPS_DIR/stock-backup-verify.txt")
    want=${want#device=}
    img="$BACKUPS_DIR/stock-$part.img"
    if [ -n "$want" ] && [ -f "$img" ]; then
      verify_exact_sha "backup-$part" "$img" "$want"
    elif [ "$STRICT_BACKUPS" -eq 1 ]; then
      fail "backup-$part" "missing $img or recorded hash in $BACKUPS_DIR/stock-backup-verify.txt"
    else
      warn "backup-$part" "missing $img or recorded hash in $BACKUPS_DIR/stock-backup-verify.txt"
    fi
  done
  for efs_part in efs sec_efs; do
    if awk -v k="$efs_part" '$1==k {found=1} END{exit !found}' "$BACKUPS_DIR/stock-backup-verify.txt" && [ -f "$BACKUPS_DIR/stock-$efs_part.img" ]; then
      pass "backup-$efs_part" "recorded in $BACKUPS_DIR/stock-backup-verify.txt"
    else
      warn "backup-$efs_part" "no $efs_part backup recorded (requires root or owner risk sign-off before flashing)"
    fi
  done
else
  msg="live partition backup manifest not found at $BACKUPS_DIR/stock-backup-verify.txt (no adb root yet; Download mode stock recovery via $STOCK_DIR)"
  if [ "$STRICT_BACKUPS" -eq 1 ]; then
    fail "backups-dir" "$msg"
  else
    warn "backups-dir" "$msg"
  fi
fi

if [ "$PROBE_DEVICE" -eq 1 ]; then
  echo "== 4. Probing connected devices (read-only) =="
  adb devices -l 2>&1 || true
  fastboot devices 2>&1 || true
  heimdall detect --verbose 2>&1 || true
fi

echo "=============================================================="
printf 'Preflight summary: %d passed, %d warning(s), %d failed\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
