#!/usr/bin/env bash
# Reproducible M1 build for lk3rd, patched r8s kernel + DTB + modules, and uniLoader boot image.
# Runs on the host via `docker run --rm` against r8s-kbuild:trixie, leaving sources/ untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${R8S_KBUILD_IMAGE:-r8s-kbuild:trixie}"
NPROC="${R8S_NPROC:-$(nproc)}"
MODE="${1:-all}" # all | lk3rd | kernel | dtbs | package

mkdir -p "$ROOT/out/work" "$ROOT/out/boot" "$ROOT/out/staging" "$ROOT/logs"

if [ ! -f "$ROOT/blobs/firmware/ath11k/QCA6390/hw2.0/amss.bin" ]; then
  echo "missing QCA6390 firmware in $ROOT/blobs/firmware/ath11k/QCA6390/hw2.0/" >&2
  exit 1
fi

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -v "$ROOT:/work" \
  -e MODE="$MODE" \
  -e NPROC="$NPROC" \
  "$IMAGE" bash -euo pipefail -c '
export HOME=/tmp
mkdir -p /tmp/bin
ln -sf /work/sources/mkbootimg/mkbootimg.py /tmp/bin/mkbootimg
export PATH="/tmp/bin:$PATH"

build_lk3rd() {
  echo "== [M1] Building lk3rd (r8s) =="
  rm -rf /work/out/work/lk3rd
  rsync -a --exclude=".git" /work/sources/lk3rd/ /work/out/work/lk3rd/
  cd /work/out/work/lk3rd
  ./build.sh r8s -t -v y
  cp build/r8s/lk3rd-r8s.img /work/out/boot/lk3rd-r8s.img
  cp build/r8s/lk3rd-r8s.tar /work/out/boot/lk3rd-r8s.tar
  sha256sum /work/out/boot/lk3rd-r8s.img /work/out/boot/lk3rd-r8s.tar | tee /work/out/boot/lk3rd-r8s.sha256
}

prepare_kernel_tree() {
  echo "== [M1] Preparing & patching kernel 6.12.0-rc5 (r8s) =="
  rm -rf /work/out/work/linux
  rsync -a --exclude=".git" /work/sources/linux/ /work/out/work/linux/
  cd /work/out/work/linux
  # Isolate git context from parent repo (/work/.git) which ignores out/.
  git init -q
  for p in /work/sources/port/kernel/patches/*.patch; do
    echo "Applying $(basename "$p")"
    git apply "$p"
  done
  if compgen -G "/work/packaging/kernel-patches/*.patch" > /dev/null; then
    for p in /work/packaging/kernel-patches/*.patch; do
      echo "Applying local $(basename "$p")"
      git apply "$p"
    done
  fi
  [ -f arch/arm64/boot/dts/exynos/exynos990-r8s.dts ] || {
    echo "ERROR: exynos990-r8s.dts missing after patches" >&2
    exit 1
  }

  mkdir -p firmware/ath11k/QCA6390/hw2.0
  cp /work/blobs/firmware/ath11k/QCA6390/hw2.0/{amss.bin,m3.bin,board-2.bin} firmware/ath11k/QCA6390/hw2.0/

  cp /work/sources/port/kernel/config/r8s.config .config
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
  REL=$(make -s ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
  echo "kernelrelease=$REL" > /work/out/boot/kernel-release.txt
}

build_dtbs() {
  prepare_kernel_tree
  [ -f /work/out/boot/Image ] && [ -f "/work/out/modules-$REL.tar.gz" ] || {
    echo "ERROR: missing Image or modules-$REL.tar.gz; run full kernel build" >&2
    exit 1
  }
  echo "== [M1] Compiling r8s DTB (-j$NPROC) =="
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$NPROC" exynos/exynos990-r8s.dtb
  cp arch/arm64/boot/dts/exynos/exynos990-r8s.dtb /work/out/boot/exynos990-r8s.dtb
  sha256sum /work/out/boot/Image /work/out/boot/exynos990-r8s.dtb "/work/out/modules-$REL.tar.gz" | tee /work/out/boot/kernel.sha256
}

build_kernel() {
  prepare_kernel_tree
  echo "== [M1] Compiling Image, dtbs, modules (-j$NPROC) =="
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$NPROC" Image dtbs modules

  cp arch/arm64/boot/Image /work/out/boot/Image
  cp arch/arm64/boot/dts/exynos/exynos990-r8s.dtb /work/out/boot/exynos990-r8s.dtb
  cp .config /work/out/boot/kernel.config

  rm -rf /work/out/staging/modstage
  make -s ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=/work/out/staging/modstage INSTALL_MOD_STRIP=1 modules_install
  rm -f "/work/out/staging/modstage/lib/modules/$REL/build" "/work/out/staging/modstage/lib/modules/$REL/source"
  tar --owner=0 --group=0 -C "/work/out/staging/modstage/lib/modules/$REL" -czf "/work/out/modules-$REL.tar.gz" .
  sha256sum /work/out/boot/Image /work/out/boot/exynos990-r8s.dtb "/work/out/modules-$REL.tar.gz" | tee /work/out/boot/kernel.sha256
}

package_uniloader() {
  echo "== [M1] Building uniLoader =="
  rm -rf /work/out/work/uniLoader
  rsync -a --exclude=".git" /work/sources/uniLoader/ /work/out/work/uniLoader/
  cd /work/out/work/uniLoader
  cp /work/out/boot/Image blob/Image
  cp /work/out/boot/exynos990-r8s.dtb blob/dtb

  # UFS boot image (empty gzip ramdisk placeholder)
  printf "" | gzip -n > /tmp/empty-ramdisk
  cp /tmp/empty-ramdisk blob/ramdisk
  make ARCH=aarch64 CROSS_COMPILE=aarch64-linux-gnu- r8s_defconfig
  make ARCH=aarch64 CROSS_COMPILE=aarch64-linux-gnu- -j"$NPROC"

  if [ -f /work/blobs/slk-stock.dtb ]; then
    python3 /work/sources/mkbootimg/mkbootimg.py \
      --header_version 2 --pagesize 2048 --base 0x10000000 \
      --kernel_offset 0x8000 --ramdisk_offset 0 --tags_offset 0x100 \
      --dtb_offset 0x01F00000 --os_version 13.0.0 --os_patch_level 2099-12 \
      --kernel uniLoader --dtb /work/blobs/slk-stock.dtb \
      --ramdisk /tmp/empty-ramdisk -o /work/out/boot/r8s-ufs.img
    sha256sum /work/out/boot/r8s-ufs.img | tee /work/out/boot/r8s-ufs.sha256
  else
    echo "WARN: /work/blobs/slk-stock.dtb missing; skipped mkbootimg for r8s-ufs.img"
  fi

  if [ -f /work/out/boot/initramfs-slim.cpio.gz ] && [ -f /work/blobs/slk-stock.dtb ]; then
    # uniLoader embeds blob/ramdisk directly via .incbin; remove start.o/uniLoader
    # so make always re-embeds the updated ramdisk, and pass an empty ramdisk to
    # mkbootimg so the initramfs is not packed twice into the Android boot image.
    cp /work/out/boot/initramfs-slim.cpio.gz blob/ramdisk
    rm -f arch/aarch64/start.o uniLoader
    make ARCH=aarch64 CROSS_COMPILE=aarch64-linux-gnu- -j"$NPROC"
    python3 /work/sources/mkbootimg/mkbootimg.py \
      --header_version 2 --pagesize 2048 --base 0x10000000 \
      --kernel_offset 0x8000 --ramdisk_offset 0 --tags_offset 0x100 \
      --dtb_offset 0x01F00000 --os_version 13.0.0 --os_patch_level 2099-12 \
      --kernel uniLoader --dtb /work/blobs/slk-stock.dtb \
      --ramdisk /tmp/empty-ramdisk -o /work/out/boot/r8s-ram.img
    RAM_BYTES=$(stat -c%s /work/out/boot/r8s-ram.img)
    if [ "$RAM_BYTES" -gt 67108864 ]; then
      echo "ERROR: r8s-ram.img ($RAM_BYTES bytes) exceeds lk3rd 64 MiB (67108864 bytes) buffer!" >&2
      rm -f /work/out/boot/r8s-ram.img
      exit 1
    fi
    sha256sum /work/out/boot/r8s-ram.img | tee /work/out/boot/r8s-ram.sha256
  fi

  if [ -f /work/out/boot/initramfs-mini.cpio.gz ] && [ -f /work/blobs/slk-stock.dtb ]; then
    cp /work/out/boot/initramfs-mini.cpio.gz blob/ramdisk
    rm -f arch/aarch64/start.o uniLoader
    make ARCH=aarch64 CROSS_COMPILE=aarch64-linux-gnu- -j"$NPROC"
    python3 /work/sources/mkbootimg/mkbootimg.py \
      --header_version 2 --pagesize 2048 --base 0x10000000 \
      --kernel_offset 0x8000 --ramdisk_offset 0 --tags_offset 0x100 \
      --dtb_offset 0x01F00000 --os_version 13.0.0 --os_patch_level 2099-12 \
      --kernel uniLoader --dtb /work/blobs/slk-stock.dtb \
      --ramdisk /tmp/empty-ramdisk -o /work/out/boot/r8s-mini.img
    MINI_BYTES=$(stat -c%s /work/out/boot/r8s-mini.img)
    if [ "$MINI_BYTES" -gt 67108864 ]; then
      echo "ERROR: r8s-mini.img ($MINI_BYTES bytes) exceeds lk3rd 64 MiB (67108864 bytes) buffer!" >&2
      rm -f /work/out/boot/r8s-mini.img
      exit 1
    fi
    sha256sum /work/out/boot/r8s-mini.img | tee /work/out/boot/r8s-mini.sha256
  fi
}

case "$MODE" in
  lk3rd) build_lk3rd ;;
  kernel) build_kernel ;;
  dtbs) build_dtbs ;;
  package) package_uniloader ;;
  all) build_lk3rd; build_kernel; package_uniloader ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac
' 2>&1 | tee "$ROOT/logs/m1-build-$MODE.log"
