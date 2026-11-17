#!/usr/bin/env bash
# Reproducible M1 builder for the Debian slim diagnostic initramfs (RAM test only).
# Full Debian rootfs was removed per 17/11/2026 decision; persistent rootfs is Arch ARM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${ROOTPW:?set ROOTPW (no default password baked in)}"
REL_FILE="$ROOT/out/boot/kernel-release.txt"

if [ ! -f "$REL_FILE" ]; then
  echo "missing $REL_FILE; run build-m1-kernel.sh first" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$REL_FILE"
MOD_TAR="$ROOT/out/modules-$kernelrelease.tar.gz"
if [ ! -f "$MOD_TAR" ]; then
  echo "missing modules tarball: $MOD_TAR" >&2
  exit 1
fi
if [ ! -f "$ROOT/packaging/rootfs-glue/r8s-usb-gadget" ]; then
  echo "missing $ROOT/packaging/rootfs-glue/r8s-usb-gadget" >&2
  exit 1
fi

mkdir -p "$ROOT/out/boot" "$ROOT/logs"

docker run --rm --privileged \
  --platform linux/arm64 \
  -v "$ROOT:/work" \
  -e ROOTPW="$ROOTPW" \
  -e KVER="$kernelrelease" \
  -e MOD_TAR="/work/out/modules-$kernelrelease.tar.gz" \
  debian:trixie bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq binutils busybox-static cpio debootstrap gzip kmod >/dev/null

echo "== [M1] Building Debian slim diagnostic initramfs =="
W=/tmp/slim
OUT=/work/out/boot/initramfs-slim.cpio.gz
rm -rf "$W"
debootstrap --arch=arm64 --variant=minbase \
  --include=systemd,systemd-sysv,udev,kmod,iproute2,evtest,i2c-tools,usbutils,psmisc,util-linux \
  trixie "$W" http://deb.debian.org/debian

rm -rf "$W"/usr/share/{doc,man,info,locale,i18n,zoneinfo,bash-completion,perl*,misc}
mkdir -p "$W/usr/share/zoneinfo"
cp /usr/share/zoneinfo/UTC "$W/usr/share/zoneinfo/" 2>/dev/null || true
rm -rf "$W"/var/lib/apt/lists/* "$W"/var/cache/* "$W"/var/lib/dpkg/*
rm -rf "$W"/usr/lib/udev/hwdb.bin "$W"/usr/lib/udev/hwdb.d "$W"/etc/udev/hwdb.bin
rm -rf "$W"/usr/lib/file "$W"/usr/lib/aarch64-linux-gnu/perl* "$W"/usr/lib/aarch64-linux-gnu/libperl.so* "$W"/usr/bin/perl*
rm -rf "$W"/usr/lib/aarch64-linux-gnu/libapt-* "$W"/usr/bin/apt* "$W"/usr/bin/dpkg* "$W"/usr/bin/sqv
find "$W" -name "*.a" -delete 2>/dev/null || true
find "$W"/usr/lib -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true
find "$W"/usr/bin "$W"/usr/sbin "$W"/bin "$W"/sbin -type f -exec strip --strip-unneeded {} + 2>/dev/null || true

cp /bin/busybox "$W/bin/busybox"
chmod +x "$W/bin/busybox"

ln -sf /sbin/init "$W/init"
: > "$W/etc/fstab"
echo "r8s-slim" > "$W/etc/hostname"
printf "127.0.0.1\tlocalhost\n127.0.1.1\tr8s-slim\n" > "$W/etc/hosts"

install -d "$W/usr/local/sbin"
install -m 0755 /work/packaging/rootfs-glue/r8s-usb-gadget "$W/usr/local/sbin/r8s-usb-gadget"

install -d "$W/etc/systemd/system/serial-getty@ttyGS0.service.d" \
           "$W/etc/systemd/system/getty@tty1.service.d"
cat > "$W/etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -L -n -l /bin/bash 115200 %I vt100
EOF
cat > "$W/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --autologin root %I \$TERM
EOF
cat > "$W/etc/systemd/system/r8s-usb-gadget.service" <<EOF
[Unit]
Description=r8s USB gadget (ACM serial + RNDIS)
DefaultDependencies=no
After=sysinit.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/r8s-usb-gadget
[Install]
WantedBy=sysinit.target
EOF

chroot "$W" /usr/bin/env ROOTPW="$ROOTPW" /bin/bash -e <<CHROOT
echo "root:\$ROOTPW" | chpasswd
systemctl enable r8s-usb-gadget.service serial-getty@ttyGS0.service
systemctl set-default multi-user.target
CHROOT

mkdir -p "$W/lib/modules/$KVER"
tar -xzf "$MOD_TAR" -C "$W/lib/modules/$KVER"
rm -rf "$W/lib/modules/$KVER"/kernel/drivers/gpu/drm/{nouveau,amd,radeon,i915} 2>/dev/null || true
rm -rf "$W/lib/modules/$KVER"/kernel/drivers/net/{ethernet,wireless/{intel,ath/ath10k,marvell,realtek,mediatek}} 2>/dev/null || true
rm -rf "$W/lib/modules/$KVER"/kernel/{fs/btrfs,sound,net/can,net/nfc,net/dsa,drivers/fpga} 2>/dev/null || true
depmod -b "$W" "$KVER"

( cd "$W" && find . -print0 | cpio --null -o -H newc --quiet ) | gzip -9 > "$OUT"
sha256sum "$OUT" | tee /work/out/boot/initramfs-slim.sha256
awk -v b=$(stat -c%s "$OUT") "BEGIN{printf \"initramfs-slim.cpio.gz: %.1f MB (budget <= 35 MB)\n\", b/1048576}"
' 2>&1 | tee "$ROOT/logs/m1-rootfs-slim.log"
