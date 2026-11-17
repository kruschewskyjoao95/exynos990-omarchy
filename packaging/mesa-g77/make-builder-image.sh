#!/usr/bin/env bash
# Build a local aarch64 Arch Linux ARM Docker image for build-mesa-g77.sh --docker.
# Same mirror and keyring as packaging/build-env/build-arch-rootfs.sh, so the
# built mesa-g77 links against the llvm-libs/libdrm versions the phone gets.
# Usage: make-builder-image.sh [image-tag]   (default r8s-alarm-builder:latest)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:-r8s-alarm-builder:latest}"
MIRROR="${R8S_ALARM_MIRROR:-https://arm-stable-mirror.omarchy.org/aarch64}"
KEYRING_PKG="archlinuxarm-keyring-20240419-2-any.pkg.tar.xz"
KEYRING_SHA256="3cb36869edfe413672a6e932cc55d7f8386e1a9d3b38663cfb3bc6fe0d146e21" # manifests/packages-aarch64-stable.tsv
OUT="$ROOT/out/build"
mkdir -p "$OUT"

docker run --rm --privileged -v "$OUT:/out" \
  -e MIRROR="$MIRROR" -e KEYRING_PKG="$KEYRING_PKG" -e KEYRING_SHA256="$KEYRING_SHA256" \
  archlinux:latest bash -euo pipefail -c '
curl -fsSL "$MIRROR/core/$KEYRING_PKG" -o /tmp/k.pkg
echo "$KEYRING_SHA256  /tmp/k.pkg" | sha256sum -c -
bsdtar -xf /tmp/k.pkg -C /
pacman-key --init >/dev/null && pacman-key --populate archlinuxarm >/dev/null

cat > /tmp/p.conf <<EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
[core]
Server = $MIRROR/\$repo
[extra]
Server = $MIRROR/\$repo
[alarm]
Server = $MIRROR/\$repo
EOF

R=/tmp/root
mkdir -p "$R"/{var/lib/pacman,dev,proc,sys}
mount --rbind /dev "$R/dev"; mount -t proc proc "$R/proc"; mount -t sysfs sys "$R/sys"
trap "umount -R \"$R/dev\" \"$R/proc\" \"$R/sys\" 2>/dev/null || true" EXIT
pacman --config /tmp/p.conf --root "$R" --dbpath "$R/var/lib/pacman" --noconfirm -Sy base base-devel archlinuxarm-keyring

# Image pacman uses the same pinned mirror; keyring is initialised on first use.
printf "Server = %s/\$repo\n" "$MIRROR" > "$R/etc/pacman.d/mirrorlist"
sed -i "s/^#\?DisableSandbox.*//; /^\[options\]/a DisableSandbox" "$R/etc/pacman.conf"
umount -R "$R/dev" "$R/proc" "$R/sys"; trap - EXIT
tar -C "$R" -cf /out/alarm-builder.tar .
'

docker import --platform linux/arm64 \
  --change 'CMD ["/bin/bash"]' \
  --change 'ENTRYPOINT ["/bin/bash","-c","pacman-key --init >/dev/null && pacman-key --populate archlinuxarm >/dev/null && exec \"$0\" \"$@\""]' \
  "$OUT/alarm-builder.tar" "$TAG"
rm -f "$OUT/alarm-builder.tar"

# Self-check: the image must run as aarch64 (via binfmt/qemu) with pacman working.
arch=$(docker run --rm --platform linux/arm64 "$TAG" uname -m)
[ "$arch" = "aarch64" ] || { echo "builder image is $arch, expected aarch64" >&2; exit 1; }
echo "OK: $TAG (aarch64)"
