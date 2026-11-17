#!/usr/bin/env bash
# Reproducible M1 builder for RAM-only diagnostic initramfs images:
#   slim (default): Debian trixie minbase + systemd + kmod + USB gadget (r8s-ram.img)
#   mini:           Tiny busybox-static liveness initramfs + DECON trigger + USB gadget (r8s-mini.img)
#   all:            Build both initramfs-slim.cpio.gz and initramfs-mini.cpio.gz
# Full Debian rootfs was removed per 17/11/2026 decision; persistent rootfs is Arch ARM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-slim}" # slim | mini | all

case "$MODE" in
  slim|mini|all) ;;
  *) echo "usage: $0 [slim|mini|all]" >&2; exit 2 ;;
esac

mkdir -p "$ROOT/out/boot" "$ROOT/logs"

build_slim() {
  : "${ROOTPW:?set ROOTPW (no default password baked in)}"
  local rel_file="$ROOT/out/boot/kernel-release.txt"
  if [ ! -f "$rel_file" ]; then
    echo "missing $rel_file; run build-m1-kernel.sh first" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  . "$rel_file"
  local mod_tar="$ROOT/out/modules-$kernelrelease.tar.gz"
  if [ ! -f "$mod_tar" ]; then
    echo "missing modules tarball: $mod_tar" >&2
    exit 1
  fi
  if [ ! -f "$ROOT/packaging/rootfs-glue/r8s-usb-gadget" ]; then
    echo "missing $ROOT/packaging/rootfs-glue/r8s-usb-gadget" >&2
    exit 1
  fi

  docker run --rm --privileged \
    --platform linux/arm64 \
    -v "$ROOT:/work" \
    -e ROOTPW="$ROOTPW" \
    -e KVER="$kernelrelease" \
    -e MOD_TAR="/work/out/modules-$kernelrelease.tar.gz" \
    debian:trixie bash -euo pipefail -c '
sha256sum --strict -c /work/out/boot/kernel.sha256
# Snapshot before the build; recheck before publishing to catch changed inputs.
cp /work/out/boot/kernel.sha256 /tmp/slim-kernel.sha256
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
tar --no-same-owner -xzf "$MOD_TAR" -C "$W/lib/modules/$KVER"
chown -R 0:0 "$W/lib/modules/$KVER"
rm -rf "$W/lib/modules/$KVER"/kernel/drivers/gpu/drm/{nouveau,amd,radeon,i915} 2>/dev/null || true
rm -rf "$W/lib/modules/$KVER"/kernel/drivers/net/{ethernet,wireless/{intel,ath/ath10k,marvell,realtek,mediatek}} 2>/dev/null || true
rm -rf "$W/lib/modules/$KVER"/kernel/{fs/btrfs,sound,net/can,net/nfc,net/dsa,drivers/fpga} 2>/dev/null || true
depmod -b "$W" "$KVER"

( cd "$W" && find . -print0 | cpio --null -o -H newc --quiet ) | gzip -9 > "$OUT"
cmp /tmp/slim-kernel.sha256 /work/out/boot/kernel.sha256
sha256sum --strict -c /tmp/slim-kernel.sha256
sha256sum "$OUT" | tee /work/out/boot/initramfs-slim.sha256
cp /tmp/slim-kernel.sha256 /work/out/boot/initramfs-slim.kernel.sha256
awk -v b=$(stat -c%s "$OUT") "BEGIN{printf \"initramfs-slim.cpio.gz: %.1f MB (budget <= 35 MB)\n\", b/1048576}"
' 2>&1 | tee "$ROOT/logs/m1-rootfs-slim.log"
}

build_mini() {
  docker run --rm --privileged \
    --platform linux/arm64 \
    -v "$ROOT:/work" \
    debian:trixie bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq busybox-static cpio gzip >/dev/null

echo "== [M1] Building minimal busybox liveness initramfs (initramfs-mini.cpio.gz) =="
W=/tmp/mini
OUT=/work/out/boot/initramfs-mini.cpio.gz
rm -rf "$W"
mkdir -p "$W"/{bin,sbin,proc,sys,dev,tmp,run,etc,root}
cp /bin/busybox "$W/bin/busybox"
chmod 0755 "$W/bin/busybox"

cat > "$W/init" <<'\''EOF'\''
#!/bin/busybox sh
/bin/busybox --install -s /bin 2>/dev/null
mount -t proc     none /proc
mount -t sysfs    none /sys
mount -t devtmpfs none /dev 2>/dev/null || true
mount -t configfs none /sys/kernel/config 2>/dev/null || true
mkdir -p /dev/pts && mount -t devpts none /dev/pts 2>/dev/null || true

echo "===================================================" > /dev/kmsg
echo " r8s mini initramfs: KERNEL IS ALIVE"               > /dev/kmsg
echo "===================================================" > /dev/kmsg

# Re-arm the DECON hardware trigger so the bootloader-lit panel keeps scanning.
if [ -e /dev/mem ]; then
  busybox devmem 0x19050070 32 0x1281 2>/dev/null && \
    echo "DECON trigger re-armed" > /dev/kmsg
fi

G=/sys/kernel/config/usb_gadget/r8s
if [ -d /sys/kernel/config/usb_gadget ]; then
  mkdir -p "$G"
  echo 0x1d6b > "$G/idVendor"
  echo 0x0104 > "$G/idProduct"
  echo 0xEF > "$G/bDeviceClass"
  echo 0x02 > "$G/bDeviceSubClass"
  echo 0x01 > "$G/bDeviceProtocol"
  mkdir -p "$G/strings/0x409"
  echo "0123456789"         > "$G/strings/0x409/serialnumber"
  echo "s20fe-port"         > "$G/strings/0x409/manufacturer"
  echo "r8s mainline ALIVE" > "$G/strings/0x409/product"
  mkdir -p "$G/configs/c.1/strings/0x409"
  echo "acm+net" > "$G/configs/c.1/strings/0x409/configuration"
  echo 500 > "$G/configs/c.1/MaxPower"
  mkdir -p "$G/functions/acm.usb0"
  if mkdir -p "$G/functions/ecm.usb0" 2>/dev/null; then
    ln -s "$G/functions/ecm.usb0" "$G/configs/c.1/" 2>/dev/null || true
  elif mkdir -p "$G/functions/rndis.usb0" 2>/dev/null; then
    ln -s "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null || true
  fi
  ln -s "$G/functions/acm.usb0" "$G/configs/c.1/" 2>/dev/null || true
  UDC=$(ls /sys/class/udc 2>/dev/null | head -n1)
  if [ -n "$UDC" ]; then
    echo "$UDC" > "$G/UDC" && echo "gadget bound to $UDC" > /dev/kmsg
  else
    echo "NO UDC FOUND" > /dev/kmsg
  fi
  ip addr add 10.42.0.2/24 dev usb0 2>/dev/null || true
  ip link set usb0 up 2>/dev/null || true
fi

while true; do
  setsid /bin/busybox sh -c '\''exec /bin/busybox sh </dev/ttyGS0 >/dev/ttyGS0 2>&1'\'' 2>/dev/null || true
  sleep 2
done &

exec /bin/busybox sh
EOF
chmod 0755 "$W/init"

( cd "$W" && find . -print0 | cpio --null -o -H newc --quiet ) | gzip -9 > "$OUT"
sha256sum "$OUT" | tee /work/out/boot/initramfs-mini.sha256
awk -v b=$(stat -c%s "$OUT") "BEGIN{printf \"initramfs-mini.cpio.gz: %.2f MB\n\", b/1048576}"
' 2>&1 | tee "$ROOT/logs/m1-rootfs-mini.log"
}

case "$MODE" in
  slim) build_slim ;;
  mini) build_mini ;;
  all)  build_mini; build_slim ;;
esac
