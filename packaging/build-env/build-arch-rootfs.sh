#!/usr/bin/env bash
# Build minimal Arch Linux ARM (aarch64) rootfs image for r8s UFS (/dev/sda32).
# Fits inside lk3rd fastboot download buffer (<= 700 MiB < 768 MiB max) and
# grows via r8s-growroot on first boot. Leaves Omarchy desktop for post-boot
# pacman installation (Item 4).
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
R8S_USER="${R8S_USER:-r8s}"
R8S_SERIAL_AUTOLOGIN="${R8S_SERIAL_AUTOLOGIN:-0}"
SSH_PUBKEY_FILE="${R8S_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
SIZE_MB="${SIZE_MB:-700}"
MIRROR="${R8S_ALARM_MIRROR:-https://arm-stable-mirror.omarchy.org/aarch64}"
KEYRING_PKG="archlinuxarm-keyring-20240419-2-any.pkg.tar.xz"
KEYRING_SHA256="3cb36869edfe413672a6e932cc55d7f8386e1a9d3b38663cfb3bc6fe0d146e21"

GLUE_DIR="$ROOT/packaging/rootfs-glue"
REQUIRED_GLUE=(
  r8s-usb-gadget
  r8s-pstore-archive
  r8s-pstore-archive.service
  r8s-heartbeat.sh
  r8s-heartbeat.service
  r8s-safe-freq
  r8s-safe-freq.service
)
for f in "${REQUIRED_GLUE[@]}"; do
  [ -f "$GLUE_DIR/$f" ] || { echo "missing $GLUE_DIR/$f" >&2; exit 1; }
done

# Vendor blobs remain local; reject missing or changed firmware before building.
(cd "$ROOT" && sha256sum --strict -c manifests/bluetooth-firmware.sha256)

if [ "$SIZE_MB" -gt 700 ]; then
  echo "SIZE_MB=$SIZE_MB exceeds 700 MiB safe budget for lk3rd 768 MiB fastboot buffer" >&2
  exit 2
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "== [arch-rootfs] DRY-RUN: user=$R8S_USER size=${SIZE_MB}MiB serial_autologin=$R8S_SERIAL_AUTOLOGIN mirror=$MIRROR =="
  exit 0
fi

: "${R8S_USERPW:?set R8S_USERPW for non-root sudo user (never hardcoded)}"

if [ ! -f "$SSH_PUBKEY_FILE" ]; then
  echo "missing SSH public key file: $SSH_PUBKEY_FILE" >&2
  exit 1
fi
if [ ! -f "$ROOT/out/boot/kernel-release.txt" ]; then
  echo "missing out/boot/kernel-release.txt; run build-m1-kernel.sh first" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$ROOT/out/boot/kernel-release.txt"
MOD_TAR="$ROOT/out/modules-$kernelrelease.tar.gz"
[ -f "$MOD_TAR" ] || { echo "missing $MOD_TAR" >&2; exit 1; }
[ -f "$ROOT/blobs/firmware/ath11k/QCA6390/hw2.0/amss.bin" ] || { echo "missing QCA6390 firmware" >&2; exit 1; }

if [ "$R8S_SERIAL_AUTOLOGIN" = "1" ]; then
  echo "WARN: R8S_SERIAL_AUTOLOGIN=1 enables unauthenticated root shell on ttyGS0 (lab bring-up only)" >&2
fi

mkdir -p "$ROOT/out/rootfs" "$ROOT/logs"
SSH_PUBKEY="$(cat "$SSH_PUBKEY_FILE")"

docker run --rm --privileged \
  -v "$ROOT:/work" \
  -e R8S_USER="$R8S_USER" \
  -e R8S_USERPW="$R8S_USERPW" \
  -e R8S_SERIAL_AUTOLOGIN="$R8S_SERIAL_AUTOLOGIN" \
  -e SSH_PUBKEY="$SSH_PUBKEY" \
  -e SIZE_MB="$SIZE_MB" \
  -e MIRROR="$MIRROR" \
  -e KEYRING_PKG="$KEYRING_PKG" \
  -e KEYRING_SHA256="$KEYRING_SHA256" \
  -e KVER="$kernelrelease" \
  -e MOD_TAR="/work/out/modules-$kernelrelease.tar.gz" \
  archlinux:latest bash -euo pipefail -c '
cd /work
sha256sum --strict -c manifests/bluetooth-firmware.sha256
echo "== [Item 3] Preparing host pacman + archlinuxarm keyring =="
for cmd in curl bsdtar mkfs.ext4 e2fsck losetup pacman pacman-key zstd xz; do
  command -v "$cmd" >/dev/null || { echo "missing tool: $cmd" >&2; exit 1; }
done

TMP_DL=/tmp/alarm-bootstrap
mkdir -p "$TMP_DL" /tmp/pacman-db /tmp/pacman-cache
curl -fsSL "$MIRROR/core/$KEYRING_PKG" -o "$TMP_DL/$KEYRING_PKG"
echo "$KEYRING_SHA256  $TMP_DL/$KEYRING_PKG" | sha256sum -c -
bsdtar -xf "$TMP_DL/$KEYRING_PKG" -C /

pacman-key --init >/dev/null
pacman-key --populate archlinuxarm >/dev/null

cat > /tmp/pacman-aarch64.conf <<EOF
[options]
HoldPkg     = pacman glibc
Architecture = aarch64
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
NoExtract   = usr/share/doc/* usr/share/man/* usr/share/info/* usr/share/gtk-doc/* usr/share/locale/*

[core]
Server = $MIRROR/\$repo

[extra]
Server = $MIRROR/\$repo

[alarm]
Server = $MIRROR/\$repo

[aur]
Server = $MIRROR/\$repo
EOF

STAGE=$(mktemp -d /work/out/rootfs/.build-XXXXXX)
IMG="$STAGE/ufs-root.img"
MNT=/tmp/archmnt
mkdir -p "$MNT"

cleanup() {
  # Never delete the chroot after a failed unmount: /dev may still be bound.
  umount -R "$MNT/sys" "$MNT/proc" "$MNT/dev" 2>/dev/null || true
  rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$MNT"/{var/lib/pacman,var/cache/pacman/pkg,etc,dev,proc,sys,tmp}
mount --rbind /dev "$MNT/dev"
mount --make-rslave "$MNT/dev"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"

echo "== [Item 3] Installing minimal Arch ARM base (aarch64) =="
pacman --config /tmp/pacman-aarch64.conf \
  --root "$MNT" \
  --dbpath "$MNT/var/lib/pacman" \
  --cachedir /tmp/pacman-cache \
  --noconfirm -Sy \
  base archlinuxarm-keyring ca-certificates networkmanager openssh sudo e2fsprogs

# Verify no generic kernel package was pulled into the image (linux-api-headers is glibc UAPI)
if pacman --root "$MNT" --dbpath "$MNT/var/lib/pacman" -Q | grep -E "^linux(-|$)" | grep -v "^linux-api-headers "; then
  echo "ERROR: generic linux kernel package detected in rootfs!" >&2
  exit 1
fi

echo "== [Item 3] Installing r8s kernel modules & QCA6390 firmware =="
mkdir -p "$MNT/usr/lib/modules/$KVER"
tar --no-same-owner -xzf "$MOD_TAR" -C "$MNT/usr/lib/modules/$KVER"
chown -R 0:0 "$MNT/usr/lib/modules/$KVER"
rm -rf "$MNT/usr/lib/modules/$KVER"/kernel/drivers/gpu/drm/{nouveau,amd,radeon,i915} 2>/dev/null || true
rm -rf "$MNT/usr/lib/modules/$KVER"/kernel/drivers/net/{ethernet,wireless/{intel,ath/ath10k,marvell,realtek,mediatek}} 2>/dev/null || true
chroot "$MNT" depmod "$KVER"

mkdir -p "$MNT/usr/lib/firmware/ath11k/QCA6390/hw2.0"
cp /work/blobs/firmware/ath11k/QCA6390/hw2.0/{amss.bin,m3.bin,board-2.bin,Notice.txt} \
  "$MNT/usr/lib/firmware/ath11k/QCA6390/hw2.0/"
# Samsung BDF (ids 255 and 4); to try: cp board-2.r8s.bin board-2.bin, then reload ath11k_pci.
cp /work/blobs/firmware/ath11k/QCA6390/hw2.0/board-2.r8s.bin "$MNT/usr/lib/firmware/ath11k/QCA6390/hw2.0/"
for f in htbtfw20.tlv htnv20.bin; do
  install -D -m 0644 "/work/blobs/r8s-device/vendor/root/firmware/$f" "$MNT/usr/lib/firmware/qca/$f"
done

echo "== [Item 3] Configuring pacman, fstab, USB gadget, growroot, watchdog, pstore, power & user =="
echo "r8s-arch" > "$MNT/etc/hostname"
printf "127.0.0.1\tlocalhost\n127.0.1.1\tr8s-arch\n" > "$MNT/etc/hosts"
printf "LABEL=r8sroot\t/\text4\tdefaults,noatime,errors=remount-ro\t0 1\n" > "$MNT/etc/fstab"
printf "LANG=C.UTF-8\n" > "$MNT/etc/locale.conf"

# Mirrorlist and pacman.conf for future on-device pacman transactions
mkdir -p "$MNT/etc/pacman.d"
printf "Server = %s/\$repo\n" "$MIRROR" > "$MNT/etc/pacman.d/mirrorlist"
IGNORE_LIST="linux linux-aarch64 linux-aarch64-headers linux-firmware* limine* mkinitcpio*"
if grep -q "^#IgnorePkg" "$MNT/etc/pacman.conf"; then
  sed -i "s/^#IgnorePkg.*/IgnorePkg = $IGNORE_LIST/" "$MNT/etc/pacman.conf"
elif grep -q "^IgnorePkg" "$MNT/etc/pacman.conf"; then
  sed -i "s/^IgnorePkg.*/IgnorePkg = $IGNORE_LIST/" "$MNT/etc/pacman.conf"
else
  sed -i "/^\[options\]/a IgnorePkg = $IGNORE_LIST" "$MNT/etc/pacman.conf"
fi
if ! grep -q "^\[alarm\]" "$MNT/etc/pacman.conf"; then
  cat >> "$MNT/etc/pacman.conf" <<EOF

[alarm]
Include = /etc/pacman.d/mirrorlist

[aur]
Include = /etc/pacman.d/mirrorlist
EOF
fi

# USB gadget recovery channel (ACM serial + RNDIS) + fixed 10.42.0.2/24 on usb0
install -d "$MNT/usr/local/sbin" "$MNT/usr/local/bin"
install -m 0755 /work/packaging/rootfs-glue/r8s-usb-gadget "$MNT/usr/local/sbin/r8s-usb-gadget"
cat > "$MNT/etc/systemd/system/r8s-usb-gadget.service" <<EOF
[Unit]
Description=r8s USB gadget (ACM serial + RNDIS) - recovery channel
DefaultDependencies=no
After=sysinit.target
Before=network-pre.target basic.target
Wants=network-pre.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/r8s-usb-gadget
[Install]
WantedBy=sysinit.target
EOF

install -d "$MNT/etc/NetworkManager/conf.d" "$MNT/etc/systemd/network"
printf "[keyfile]\nunmanaged-devices=interface-name:usb0\n" > "$MNT/etc/NetworkManager/conf.d/10-r8s-unmanaged-usb.conf"
cat > "$MNT/etc/systemd/network/10-usb0.network" <<EOF
[Match]
Name=usb0

[Network]
Address=10.42.0.2/24
ConfigureWithoutCarrier=yes
EOF

cat > "$MNT/etc/systemd/system/r8s-usb0-addr.service" <<EOF
[Unit]
Description=Static address on the r8s USB gadget link
After=r8s-usb-gadget.service
Requires=r8s-usb-gadget.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\''ip addr add 10.42.0.2/24 dev usb0 2>/dev/null || true; ip link set usb0 up'\''
[Install]
WantedBy=multi-user.target
EOF

install -d "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
if [ "$R8S_SERIAL_AUTOLOGIN" = "1" ]; then
  # Opt-in unauthenticated root shell for early M2 serial bring-up only.
  cat > "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -L -n -l /bin/bash 115200 %I vt100
EOF
else
  # Authenticated login prompt on ttyGS0 (matches r8s-sshd-hardening; log in as r8s).
  cat > "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -L 115200 %I vt100
EOF
fi

# One-shot growroot on /dev/sda32 (verified userdata block device)
cat > "$MNT/usr/local/sbin/r8s-growroot" <<EOF
#!/bin/sh
set -e
resize2fs /dev/sda32 && systemctl disable r8s-growroot.service
EOF
chmod 0755 "$MNT/usr/local/sbin/r8s-growroot"
cat > "$MNT/etc/systemd/system/r8s-growroot.service" <<EOF
[Unit]
Description=Grow the r8s root filesystem to fill /dev/sda32
After=local-fs.target
ConditionPathExists=/dev/sda32
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/r8s-growroot
[Install]
WantedBy=multi-user.target
EOF

# Hardware glue from port: charger limit, Wi-Fi watchdog, software watchdog (no DT watchdog),
# RCU-stall panic/pstore archiving, ramoops heartbeat, CPU freq pin, and safe powerkey/no-sleep.
install -m 0755 /work/sources/port/device/r8s-charge-limit.sh "$MNT/usr/local/bin/r8s-charge-limit.sh"
install -d "$MNT/etc/udev/rules.d"
install -m 0644 /work/sources/port/device/r8s-charge-limit.rules "$MNT/etc/udev/rules.d/90-r8s-charge-limit.rules"

install -m 0755 /work/sources/port/device/r8s-netwatch.sh "$MNT/usr/local/bin/r8s-netwatch.sh"
install -m 0644 /work/sources/port/device/r8s-netwatch.service "$MNT/etc/systemd/system/r8s-netwatch.service"

install -d "$MNT/etc/modules-load.d" "$MNT/etc/modprobe.d" "$MNT/etc/systemd/system.conf.d" "$MNT/etc/sysctl.d"
printf "softdog\n" > "$MNT/etc/modules-load.d/r8s-softdog.conf"
printf "options softdog soft_margin=60 soft_panic=0 nowayout=0\n" > "$MNT/etc/modprobe.d/r8s-softdog.conf"
cat > "$MNT/etc/systemd/system.conf.d/10-r8s-watchdog.conf" <<EOF
[Manager]
RuntimeWatchdogSec=45s
RebootWatchdogSec=120s
EOF
cat > "$MNT/etc/sysctl.d/90-r8s-recovery.conf" <<EOF
kernel.panic_on_rcu_stall = 1
kernel.panic = 10
kernel.panic_print = 0x40
kernel.printk = 7 4 1 7
EOF

install -m 0755 /work/packaging/rootfs-glue/r8s-pstore-archive "$MNT/usr/local/sbin/r8s-pstore-archive"
install -m 0644 /work/packaging/rootfs-glue/r8s-pstore-archive.service "$MNT/etc/systemd/system/r8s-pstore-archive.service"
install -m 0755 /work/packaging/rootfs-glue/r8s-heartbeat.sh "$MNT/usr/local/bin/r8s-heartbeat.sh"
install -m 0644 /work/packaging/rootfs-glue/r8s-heartbeat.service "$MNT/etc/systemd/system/r8s-heartbeat.service"
install -m 0755 /work/packaging/rootfs-glue/r8s-safe-freq "$MNT/usr/local/sbin/r8s-safe-freq"
install -m 0644 /work/packaging/rootfs-glue/r8s-safe-freq.service "$MNT/etc/systemd/system/r8s-safe-freq.service"

install -d "$MNT/etc/systemd/sleep.conf.d" "$MNT/etc/systemd/logind.conf.d"
printf "[Sleep]\nAllowSuspend=no\n" > "$MNT/etc/systemd/sleep.conf.d/90-r8s.conf"
cat > "$MNT/etc/systemd/logind.conf.d/10-r8s.conf" <<EOF
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
PowerKeyIgnoreInhibited=yes
HoldoffTimeoutSec=10s
EOF

# Hardened SSH: key-only auth, no root SSH login
install -d "$MNT/etc/ssh/sshd_config.d"
cat > "$MNT/etc/ssh/sshd_config.d/10-r8s.conf" <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF

# Non-root sudo user + key-only SSH + target pacman-key initialization
install -d "$MNT/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) ALL" > "$MNT/etc/sudoers.d/10-wheel"
chmod 0440 "$MNT/etc/sudoers.d/10-wheel"

chroot "$MNT" /usr/bin/env R8S_USER="$R8S_USER" R8S_USERPW="$R8S_USERPW" /bin/bash -e <<CHROOT
pacman-key --init
pacman-key --populate archlinuxarm
gpgconf --homedir /etc/pacman.d/gnupg --kill all || true
passwd -l root
useradd -m -G wheel -s /bin/bash "\$R8S_USER"
echo "\$R8S_USER:\$R8S_USERPW" | chpasswd
systemctl enable \
  NetworkManager.service \
  systemd-networkd.service \
  sshd.service \
  systemd-pstore.service \
  r8s-usb-gadget.service \
  r8s-usb0-addr.service \
  r8s-growroot.service \
  r8s-netwatch.service \
  r8s-pstore-archive.service \
  r8s-heartbeat.service \
  r8s-safe-freq.service \
  serial-getty@ttyGS0.service
systemctl set-default multi-user.target
CHROOT

install -d -m 0700 "$MNT/home/$R8S_USER/.ssh"
printf "%s\n" "$SSH_PUBKEY" > "$MNT/home/$R8S_USER/.ssh/authorized_keys"
chmod 0600 "$MNT/home/$R8S_USER/.ssh/authorized_keys"
chroot "$MNT" chown -R "$R8S_USER:$R8S_USER" "/home/$R8S_USER/.ssh"

# Record installed package manifest before cleanup
pacman --root "$MNT" --dbpath "$MNT/var/lib/pacman" -Q > "$STAGE/arch-base-packages.txt"
rm -rf "$MNT/var/cache/pacman/pkg"/* "$MNT/var/lib/pacman/sync"/* "$MNT/tmp"/* "$MNT/var/tmp"/*

umount -R "$MNT/sys" "$MNT/proc" "$MNT/dev"
echo "== [Item 3] Target rootfs tree size before packing =="
du -sh "$MNT"

truncate -s "${SIZE_MB}M" "$IMG"
mkfs.ext4 -q -F -L r8sroot -m 0 -O ^metadata_csum_seed -d "$MNT" "$IMG"
rm -rf "$MNT"

e2fsck -fn "$IMG"
BYTES=$(stat -c%s "$IMG")
if [ "$BYTES" -gt 734003200 ]; then
  echo "ERROR: ufs-root.img ($BYTES bytes) exceeds 700 MiB!" >&2
  exit 1
fi
(cd "$STAGE" && sha256sum ufs-root.img) > "$STAGE/ufs-root.sha256"
# Publish only after validation; the checksum is the last completion marker.
# shortcut: the three renames are not a transaction; use versioned bundles for concurrent builds.
mv "$IMG" /work/out/rootfs/ufs-root.img
mv "$STAGE/arch-base-packages.txt" /work/out/rootfs/arch-base-packages.txt
mv "$STAGE/ufs-root.sha256" /work/out/rootfs/ufs-root.sha256
cat /work/out/rootfs/ufs-root.sha256
' 2>&1 | tee "$ROOT/logs/m1-arch-rootfs.log"
