#!/usr/bin/env bash
# Offline verification of M1 boot/rootfs artifacts, packaging scripts, and M4 recipe syntax.
# Read-only with respect to out/, blobs/, and any connected devices (never touches a phone).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS [%s] %s\n' "$1" "$2"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL [%s] %s\n' "$1" "$2" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required host command: $1" >&2
    exit 2
  }
}

# Verify a file exists, is non-empty, and matches the digest recorded in a .sha256 manifest.
# Manifests produced inside Docker carry /work/... paths, so match by digest + basename.
verify_sha256_entry() {
  local label=$1 file=$2 sha_file=$3
  if [ ! -f "$file" ]; then
    fail "$label" "missing artifact: $file"
    return
  fi
  if [ ! -s "$file" ]; then
    fail "$label" "empty artifact: $file"
    return
  fi
  if [ ! -f "$sha_file" ]; then
    fail "$label" "missing sha256 file: $sha_file"
    return
  fi
  local base want have
  base=$(basename "$file")
  want=$(awk -v b="$base" '$2 ~ ("(^|/)" b "$") {print $1; exit}' "$sha_file")
  if [ -z "$want" ]; then
    fail "$label" "no entry for $base in $sha_file"
    return
  fi
  have=$(sha256sum "$file" | awk '{print $1}')
  if [ "$have" != "$want" ]; then
    fail "$label" "sha256 mismatch for $base (expected $want, got $have)"
    return
  fi
  pass "$label" "$base ($(stat -c%s "$file") bytes, sha256=$have)"
}

verify_bootimg_header() {
  local label=$1 img=$2 expected_dtb_bytes=$3 expect_empty_ramdisk=$4
  local unpack_dir="$TMP/unpack-$label"
  local hdr="$TMP/header-$label.txt"
  mkdir -p "$unpack_dir"

  if ! python3 "$ROOT/sources/mkbootimg/unpack_bootimg.py" --boot_img "$img" --out "$unpack_dir" >"$hdr" 2>&1; then
    fail "$label-unpack" "unpack_bootimg.py failed on $img"
    cat "$hdr" >&2
    return
  fi

  local magic hdr_ver pagesize dtb_size ramdisk_size kernel_size
  magic=$(awk -F': ' '$1=="boot magic" {print $2}' "$hdr")
  hdr_ver=$(awk -F': ' '$1=="boot image header version" {print $2}' "$hdr")
  pagesize=$(awk -F': ' '$1=="page size" {print $2}' "$hdr")
  dtb_size=$(awk -F': ' '$1=="dtb size" {print $2}' "$hdr")
  ramdisk_size=$(awk -F': ' '$1=="ramdisk size" {print $2}' "$hdr")
  kernel_size=$(awk -F': ' '$1=="kernel_size" {print $2}' "$hdr")

  if [ "$magic" != "ANDROID!" ] || [ "$hdr_ver" != "2" ] || [ "$pagesize" != "2048" ]; then
    fail "$label-header" "unexpected header (magic=$magic ver=$hdr_ver pagesize=$pagesize)"
    return
  fi
  if [ "$dtb_size" != "$expected_dtb_bytes" ]; then
    fail "$label-dtb-size" "dtb size mismatch (expected $expected_dtb_bytes, got $dtb_size)"
    return
  fi
  if [ "$expect_empty_ramdisk" = "1" ] && [ "${ramdisk_size:-0}" -gt 32 ]; then
    fail "$label-ramdisk" "expected empty gzip placeholder ramdisk in mkbootimg, got $ramdisk_size bytes (double-packed?)"
    return
  fi
  if [ "${kernel_size:-0}" -le 0 ]; then
    fail "$label-kernel" "invalid kernel_size=$kernel_size"
    return
  fi

  pass "$label-header" "ANDROID! v2, pagesize=$pagesize, kernel_size=$kernel_size, ramdisk_size=$ramdisk_size, dtb_size=$dtb_size"
}

for cmd in bash python3 sha256sum stat awk grep gzip tar e2fsck debugfs; do
  require_cmd "$cmd"
done

echo "== 1. Verifying out/boot/* and kernel outputs =="

REL_FILE="$ROOT/out/boot/kernel-release.txt"
if [ ! -f "$REL_FILE" ]; then
  fail "kernel-release" "missing $REL_FILE"
  KVER=""
else
  KVER=$(sed -n 's/^kernelrelease=//p' "$REL_FILE" | head -n1)
  if [ -z "$KVER" ]; then
    fail "kernel-release" "empty kernelrelease in $REL_FILE"
  else
    pass "kernel-release" "kernelrelease=$KVER"
  fi
fi

verify_sha256_entry "lk3rd-img" "$ROOT/out/boot/lk3rd-r8s.img" "$ROOT/out/boot/lk3rd-r8s.sha256"
verify_sha256_entry "lk3rd-tar" "$ROOT/out/boot/lk3rd-r8s.tar" "$ROOT/out/boot/lk3rd-r8s.sha256"
verify_sha256_entry "kernel-Image" "$ROOT/out/boot/Image" "$ROOT/out/boot/kernel.sha256"
verify_sha256_entry "kernel-dtb" "$ROOT/out/boot/exynos990-r8s.dtb" "$ROOT/out/boot/kernel.sha256"
[ -n "$KVER" ] && verify_sha256_entry "kernel-modules" "$ROOT/out/modules-$KVER.tar.gz" "$ROOT/out/boot/kernel.sha256"
verify_sha256_entry "initramfs-slim" "$ROOT/out/boot/initramfs-slim.cpio.gz" "$ROOT/out/boot/initramfs-slim.sha256"
verify_sha256_entry "initramfs-mini" "$ROOT/out/boot/initramfs-mini.cpio.gz" "$ROOT/out/boot/initramfs-mini.sha256"
verify_sha256_entry "r8s-ufs-img" "$ROOT/out/boot/r8s-ufs.img" "$ROOT/out/boot/r8s-ufs.sha256"
verify_sha256_entry "r8s-ram-img" "$ROOT/out/boot/r8s-ram.img" "$ROOT/out/boot/r8s-ram.sha256"
verify_sha256_entry "r8s-mini-img" "$ROOT/out/boot/r8s-mini.img" "$ROOT/out/boot/r8s-mini.sha256"

# Check kernel.config exists and FDT magic on exynos990-r8s.dtb
if [ -s "$ROOT/out/boot/kernel.config" ]; then
  pass "kernel-config" "kernel.config ($(stat -c%s "$ROOT/out/boot/kernel.config") bytes)"
else
  fail "kernel-config" "missing or empty out/boot/kernel.config"
fi

if [ -f "$ROOT/out/boot/exynos990-r8s.dtb" ]; then
  dtb_magic=$(od -An -tx1 -N4 "$ROOT/out/boot/exynos990-r8s.dtb" | tr -d ' \n')
  if [ "$dtb_magic" = "d00dfeed" ]; then
    pass "dtb-magic" "exynos990-r8s.dtb has FDT magic 0xd00dfeed"
  else
    fail "dtb-magic" "unexpected DTB magic $dtb_magic"
  fi
fi

# Check gzip integrity of initramfs-slim.cpio.gz, initramfs-mini.cpio.gz, and modules tarball
if [ -f "$ROOT/out/boot/initramfs-slim.cpio.gz" ] && gzip -t "$ROOT/out/boot/initramfs-slim.cpio.gz" 2>/dev/null; then
  pass "initramfs-gzip" "initramfs-slim.cpio.gz gzip integrity ok"
else
  fail "initramfs-gzip" "initramfs-slim.cpio.gz failed gzip -t"
fi

if [ -f "$ROOT/out/boot/initramfs-mini.cpio.gz" ] && gzip -t "$ROOT/out/boot/initramfs-mini.cpio.gz" 2>/dev/null; then
  pass "initramfs-mini-gzip" "initramfs-mini.cpio.gz gzip integrity ok"
else
  fail "initramfs-mini-gzip" "initramfs-mini.cpio.gz failed gzip -t"
fi

if [ -n "$KVER" ] && [ -f "$ROOT/out/modules-$KVER.tar.gz" ] && tar -tzf "$ROOT/out/modules-$KVER.tar.gz" ./modules.dep >/dev/null 2>&1; then
  pass "modules-tar" "modules-$KVER.tar.gz contains ./modules.dep"
else
  fail "modules-tar" "modules tarball missing or lacks ./modules.dep"
fi

# Enforce 64 MiB (67108864 bytes) lk3rd fastboot boot buffer limit on r8s-ram.img & r8s-mini.img
for ram_img in "$ROOT/out/boot/r8s-ram.img" "$ROOT/out/boot/r8s-mini.img"; do
  ram_label=$(basename "$ram_img" .img)
  if [ -f "$ram_img" ]; then
    ram_bytes=$(stat -c%s "$ram_img")
    if [ "$ram_bytes" -le 67108864 ]; then
      pass "${ram_label}-limit" "$(basename "$ram_img") ($ram_bytes bytes <= 67108864 byte lk3rd limit)"
    else
      fail "${ram_label}-limit" "$(basename "$ram_img") ($ram_bytes bytes) exceeds 67108864 byte lk3rd limit"
    fi
  fi
done

# Enforce 2 MiB (2097152 bytes) size of lk3rd-r8s.img
if [ -f "$ROOT/out/boot/lk3rd-r8s.img" ]; then
  lk_bytes=$(stat -c%s "$ROOT/out/boot/lk3rd-r8s.img")
  if [ "$lk_bytes" -le 2097152 ]; then
    pass "lk3rd-size" "lk3rd-r8s.img ($lk_bytes bytes <= 2097152 bytes)"
  else
    fail "lk3rd-size" "lk3rd-r8s.img ($lk_bytes bytes) exceeds 2097152 bytes"
  fi
fi

# Verify unpack_bootimg headers
if [ -f "$ROOT/blobs/slk-stock.dtb" ]; then
  stock_dtb_bytes=$(stat -c%s "$ROOT/blobs/slk-stock.dtb")
  verify_bootimg_header "r8s-ram" "$ROOT/out/boot/r8s-ram.img" "$stock_dtb_bytes" 1
  verify_bootimg_header "r8s-mini" "$ROOT/out/boot/r8s-mini.img" "$stock_dtb_bytes" 1
  verify_bootimg_header "r8s-ufs" "$ROOT/out/boot/r8s-ufs.img" "$stock_dtb_bytes" 1
  verify_bootimg_header "lk3rd" "$ROOT/out/boot/lk3rd-r8s.img" "$stock_dtb_bytes" 1
else
  fail "slk-stock-dtb" "missing blobs/slk-stock.dtb"
fi

echo "== 2. Verifying out/rootfs/ufs-root.img and arch-base-packages.txt =="

UFS_IMG="$ROOT/out/rootfs/ufs-root.img"
PKG_LIST="$ROOT/out/rootfs/arch-base-packages.txt"

verify_sha256_entry "ufs-root-img" "$UFS_IMG" "$ROOT/out/rootfs/ufs-root.sha256"

if [ -f "$UFS_IMG" ]; then
  ufs_bytes=$(stat -c%s "$UFS_IMG")
  if [ "$ufs_bytes" -le 734003200 ]; then
    pass "ufs-root-limit" "ufs-root.img ($ufs_bytes bytes <= 734003200 byte 700 MiB budget)"
  else
    fail "ufs-root-limit" "ufs-root.img ($ufs_bytes bytes) exceeds 734003200 bytes"
  fi

  if e2fsck -fn "$UFS_IMG" >"$TMP/e2fsck.out" 2>&1; then
    summary=$(tail -n1 "$TMP/e2fsck.out")
    pass "ufs-e2fsck" "$summary"
  else
    fail "ufs-e2fsck" "e2fsck -fn failed on $UFS_IMG"
    cat "$TMP/e2fsck.out" >&2
  fi

  # Check sudo 04755 via debugfs
  sudo_stat=$(debugfs -R "stat /usr/bin/sudo" "$UFS_IMG" 2>/dev/null || true)
  if echo "$sudo_stat" | grep -qE "Mode:[[:space:]]*04755"; then
    pass "ufs-sudo-mode" "/usr/bin/sudo mode is 04755"
  else
    fail "ufs-sudo-mode" "/usr/bin/sudo missing or mode != 04755"
  fi

  # Check r8s authorized_keys via debugfs (mode 0600, uid/gid 1000, non-empty)
  ak_stat=$(debugfs -R "stat /home/r8s/.ssh/authorized_keys" "$UFS_IMG" 2>/dev/null || true)
  ak_size=$(echo "$ak_stat" | sed -n 's/^User:.*Size:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)
  if echo "$ak_stat" | grep -qE "Mode:[[:space:]]*0600" && \
     echo "$ak_stat" | grep -qE "User:[[:space:]]*1000[[:space:]]+Group:[[:space:]]*1000" && \
     [ "${ak_size:-0}" -gt 0 ]; then
    pass "ufs-ssh-key" "/home/r8s/.ssh/authorized_keys mode=0600 uid=1000 gid=1000 size=${ak_size}B"
  else
    fail "ufs-ssh-key" "/home/r8s/.ssh/authorized_keys missing or wrong permissions/ownership"
  fi

  # Check kernel modules tree (owned 0:0), watchdog/pstore/recovery glue & sshd hardening inside ufs-root.img
  check_ufs_file() {
    local label=$1 path=$2 require_root_owner=${3:-0}
    local st
    st=$(debugfs -R "stat $path" "$UFS_IMG" 2>/dev/null || true)
    if ! echo "$st" | grep -q "Type: regular"; then
      fail "$label" "$path missing in rootfs"
      return
    fi
    if [ "$require_root_owner" = "1" ]; then
      if echo "$st" | grep -qE "User:[[:space:]]*0[[:space:]]+Group:[[:space:]]*0"; then
        pass "$label" "$path present (0:0)"
      else
        local ug
        ug=$(echo "$st" | sed -n 's/^User:[[:space:]]*\([0-9]*\)[[:space:]]*Group:[[:space:]]*\([0-9]*\).*/\1:\2/p' | head -n1)
        fail "$label" "$path owned by ${ug:-unknown}, expected 0:0"
      fi
    else
      pass "$label" "$path present"
    fi
  }

  if [ -n "$KVER" ]; then
    check_ufs_file "ufs-modules-dep" "/usr/lib/modules/$KVER/modules.dep" 1
    check_ufs_file "ufs-panfrost-ko" "/usr/lib/modules/$KVER/kernel/drivers/gpu/drm/panfrost/panfrost.ko" 1
  else
    fail "ufs-modules" "cannot check modules without kernelrelease"
  fi

  check_ufs_file "ufs-sshd-conf" "/etc/ssh/sshd_config.d/10-r8s.conf" 1
  check_ufs_file "ufs-softdog-load" "/etc/modules-load.d/r8s-softdog.conf" 1
  check_ufs_file "ufs-watchdog-conf" "/etc/systemd/system.conf.d/10-r8s-watchdog.conf" 1
  check_ufs_file "ufs-recovery-sysctl" "/etc/sysctl.d/90-r8s-recovery.conf" 1
  check_ufs_file "ufs-pstore-archive" "/etc/systemd/system/r8s-pstore-archive.service" 1
fi

if [ -f "$PKG_LIST" ] && [ -s "$PKG_LIST" ]; then
  pkg_count=$(wc -l < "$PKG_LIST" | tr -d ' ')
  bad_kernel_pkgs=$(grep -E '^linux(-|$)' "$PKG_LIST" | grep -v '^linux-api-headers ' || true)
  if [ -z "$bad_kernel_pkgs" ]; then
    pass "arch-pkg-list" "$pkg_count packages listed; no generic linux-* kernel package (linux-api-headers only)"
  else
    fail "arch-pkg-list" "forbidden kernel package(s) in arch-base-packages.txt: $bad_kernel_pkgs"
  fi
else
  fail "arch-pkg-list" "missing or empty $PKG_LIST"
fi

echo "== 3. Checking script syntax (bash -n) and dry-run hooks =="

while IFS= read -r script; do
  rel=${script#"$ROOT/"}
  if bash -n "$script"; then
    pass "bash-n" "$rel"
  else
    fail "bash-n" "$rel failed syntax check"
  fi
done < <(find "$ROOT/packaging" "$ROOT/checks" -type f \( -name '*.sh' -o -name 'r8s-usb-gadget' -o -name 'PKGBUILD' -o -name 'mesa-g77-run' \) | sort)

if [ -f "$ROOT/packaging/omarchy/install-omarchy-r8s.sh" ]; then
  if "$ROOT/packaging/omarchy/install-omarchy-r8s.sh" --dry-run >"$TMP/omarchy-dry.out" 2>&1; then
    pass "dry-run-omarchy" "install-omarchy-r8s.sh --dry-run ok"
  else
    fail "dry-run-omarchy" "install-omarchy-r8s.sh --dry-run failed"
    cat "$TMP/omarchy-dry.out" >&2
  fi
fi

if [ -f "$ROOT/packaging/host-tools/m2-preflight.sh" ]; then
  if "$ROOT/packaging/host-tools/m2-preflight.sh" --help >"$TMP/m2-help.out" 2>&1; then
    pass "m2-preflight-help" "m2-preflight.sh --help ok"
  else
    fail "m2-preflight-help" "m2-preflight.sh --help failed"
  fi
fi

echo "=============================================================="
printf 'Summary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
