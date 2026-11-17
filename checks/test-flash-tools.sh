#!/usr/bin/env bash
# Simulated ADB dry-run and failure-mode tests for packaging/host-tools/.
# Never touches any real device; uses a temporary mock `adb` in PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/packaging/host-tools"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/bk" "$TMP/dev"

# Build a 1 MiB stock boot image and a 512 KiB candidate image
dd if=/dev/zero bs=1024 count=1024 status=none | tr '\0' 'S' > "$TMP/bk/stock-boot.img"
dd if=/dev/zero bs=1024 count=512  status=none | tr '\0' 'N' > "$TMP/new-boot.img"
dd if=/dev/zero bs=1024 count=2048 status=none | tr '\0' 'B' > "$TMP/big-boot.img"
cp "$TMP/bk/stock-boot.img" "$TMP/dev/boot.bin"

STOCK_HASH=$(sha256sum "$TMP/bk/stock-boot.img" | awk '{print $1}')
printf 'boot device=%s\n' "$STOCK_HASH" > "$TMP/bk/stock-backup-verify.txt"

cat > "$TMP/bin/adb" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
STATE="${MOCK_ADB_STATE:?}"

if [ "${1:-}" = "devices" ]; then
  if [ "${MOCK_MULTI:-0}" = "1" ]; then
    printf 'List of devices attached\nR5CR1000001\tdevice\nR5CR1000002\tdevice\n'
  else
    printf 'List of devices attached\nR5CR1000001\tdevice\n'
  fi
  exit 0
fi

SERIAL=""
if [ "${1:-}" = "-s" ]; then
  SERIAL="$2"; shift 2
fi

case "${1:-}" in
  get-state)
    echo "device"
    ;;
  push)
    cp "$2" "$STATE/pushed.img"
    ;;
  exec-out)
    shift
    cat "$STATE/boot.bin"
    ;;
  shell)
    shift
    cmd="$*"
    case "$cmd" in
      "id -u") echo "${MOCK_UID:-0}" ;;
      *"readlink -f /dev/block/by-name/boot"*) echo "/dev/block/sda14" ;;
      *"readlink -f /dev/block/by-name/recovery"*) echo "/dev/block/sda15" ;;
      *"/sys/class/block/sda14/size"*) echo "2048" ;; # 1 MiB
      *"/sys/class/power_supply/battery/capacity"*) echo "${MOCK_BATT:-85}" ;;
      *"dd if=/dev/block/sda14"*"sha256sum"*)
        if [ "${MOCK_READBACK_CORRUPT:-0}" = "1" ] && [ -f "$STATE/wrote" ]; then
          echo "0000000000000000000000000000000000000000000000000000000000000000  -"
        else
          sha256sum "$STATE/boot.bin"
        fi
        ;;
      *"dd if=/data/local/tmp/flash-boot.img"*|*"dd if=/data/local/tmp/restore-"*)
        touch "$STATE/wrote"
        cp "$STATE/pushed.img" "$STATE/boot.bin"
        ;;
      *"rm -f /data/local/tmp/"*)
        rm -f "$STATE/pushed.img"
        ;;
      *)
        echo "unexpected mock adb shell: $cmd" >&2
        exit 99
        ;;
    esac
    ;;
  *)
    echo "unexpected mock adb cmd: $*" >&2
    exit 99
    ;;
esac
MOCK
chmod +x "$TMP/bin/adb"

export PATH="$TMP/bin:$PATH"
export MOCK_ADB_STATE="$TMP/dev"
export R8S_BACKUPS_DIR="$TMP/bk"

expect_fail() {
  local label=$1 expected_rc=$2; shift 2
  set +e
  "$@" >"$TMP/out.txt" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne "$expected_rc" ]; then
    echo "FAIL [$label]: expected rc=$expected_rc got rc=$rc"
    cat "$TMP/out.txt"
    exit 1
  fi
  echo "PASS [$label] (rc=$rc)"
}

# 1. Non-allowlisted partition rejected
expect_fail "wrong-partition" 3 "$TOOLS/restore-stock.sh" userdata

# 2. Multi-device ambiguity rejected without ANDROID_SERIAL
MOCK_MULTI=1 expect_fail "multi-device" 4 "$TOOLS/flash-boot.sh" "$TMP/new-boot.img"

# 3. Non-root ADB rejected
MOCK_UID=2000 expect_fail "non-root-adb" 5 "$TOOLS/flash-boot.sh" "$TMP/new-boot.img"

# 4. Oversized image rejected
expect_fail "oversized-image" 7 "$TOOLS/flash-boot.sh" "$TMP/big-boot.img"

# 5. Low battery rejected
MOCK_BATT=15 expect_fail "low-battery" 8 "$TOOLS/flash-boot.sh" "$TMP/new-boot.img"

# 6. Missing stock-backup-verify.txt rejected in restore-stock.sh (previously bypassed!)
mv "$TMP/bk/stock-backup-verify.txt" "$TMP/bk/stock-backup-verify.txt.bak"
expect_fail "missing-hash-manifest-restore" 8 "$TOOLS/restore-stock.sh" boot
expect_fail "missing-hash-manifest-flash" 6 "$TOOLS/flash-boot.sh" "$TMP/new-boot.img"
mv "$TMP/bk/stock-backup-verify.txt.bak" "$TMP/bk/stock-backup-verify.txt"

# 7. Dry-run succeeds without modifying mock boot.bin
"$TOOLS/flash-boot.sh" "$TMP/new-boot.img" >/dev/null
[ "$(sha256sum "$TMP/dev/boot.bin" | awk '{print $1}')" = "$STOCK_HASH" ] || exit 1
echo "PASS [dry-run-flash]"

"$TOOLS/restore-stock.sh" boot >/dev/null
echo "PASS [dry-run-restore]"

# 8. Readback mismatch triggers exit 9
MOCK_READBACK_CORRUPT=1 expect_fail "readback-mismatch" 9 "$TOOLS/flash-boot.sh" "$TMP/new-boot.img" --write

# 9. Valid write + restore round-trip on mock device
cp "$TMP/bk/stock-boot.img" "$TMP/dev/boot.bin"
rm -f "$TMP/dev/wrote"
"$TOOLS/flash-boot.sh" "$TMP/new-boot.img" --write >/dev/null
"$TOOLS/restore-stock.sh" boot --write >/dev/null
[ "$(sha256sum "$TMP/dev/boot.bin" | awk '{print $1}')" = "$STOCK_HASH" ] || exit 1
echo "PASS [mock-write-and-restore-roundtrip]"
