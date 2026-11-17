#!/usr/bin/env bash
# Real package transaction in disposable ARM64 Docker; never mounts host devices.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/validation/arm64"
mkdir -p "$OUT" "$ROOT/logs"
BUILDER_ID=$(docker image inspect r8s-alarm-builder:latest --format '{{.Id}}')
printf '%s\n' "$BUILDER_ID" > "$OUT/builder-image.txt"
# Retain the stopped container as a reviewable artifact, like the package cache.
docker run --cidfile "$OUT/container-$(date +%s%N).id" --platform linux/arm64 --entrypoint /bin/bash \
  -v "$ROOT:/work:ro" -v "$OUT:/results" \
  "$BUILDER_ID" -euo pipefail -c '
uname -m
pacman-key --init >/dev/null
pacman-key --populate archlinuxarm >/dev/null
curl -fsSL https://pkgs.omarchy.org/stable/aarch64/omarchy-keyring-20251027-1-any.pkg.tar.zst -o /tmp/keyring.pkg.tar.zst
echo "cce48c07cfc2b97e198df1bc81705db2921685032fe39f18b4ddfd84264b5967  /tmp/keyring.pkg.tar.zst" | sha256sum -c -
pacman -U --noconfirm /tmp/keyring.pkg.tar.zst
pacman-key --populate omarchy
awk '\''/^\[core\]/ { print "[omarchy]\nSigLevel = Required DatabaseOptional\nServer = https://pkgs.omarchy.org/stable/aarch64\n" } {print}'\'' /etc/pacman.conf > /tmp/pacman.conf
sed -i "/^\[options\]/a IgnorePkg = linux linux-aarch64 linux-aarch64-headers linux-firmware* limine* mkinitcpio*" /tmp/pacman.conf
mapfile -t packages < /work/packaging/omarchy/desktop-packages.txt
mkdir -p /results/pkgcache
pacman --config /tmp/pacman.conf --cachedir /results/pkgcache -Syu --noconfirm --needed "${packages[@]}"
pacman -Q > /results/installed-packages.txt
if pacman -Qq | grep -E "^(linux($|-)|limine|mkinitcpio)" | grep -v "^linux-api-headers$"; then
  echo "ERROR: forbidden boot package installed" >&2; exit 1
fi
for cmd in Hyprland qs foot firefox squeekboard; do command -v "$cmd"; done
systemd-analyze verify --man=no /usr/lib/systemd/system/sddm.service
# Model only target identity; execute the real installer inside this container.
printf "samsung,r8s\0samsung,exynos990\0" > /results/r8s-compatible
useradd -m -G wheel r8s
mkdir -p /tmp/r8s-installer
sed "s@/sys/firmware/devicetree/base/compatible@/results/r8s-compatible@g" /work/packaging/omarchy/install-omarchy-r8s.sh > /tmp/r8s-installer/install.sh
cp /work/packaging/omarchy/desktop-packages.txt /tmp/r8s-installer/
cp /tmp/pacman.conf /etc/pacman.conf
ln -s /results/pkgcache /tmp/r8s-cache
sed -i "/^\[options\]/a CacheDir = /tmp/r8s-cache" /etc/pacman.conf
R8S_MESA_G77_PKG=/work/out/packages/mesa-g77-26.3.0_devel.7d6bb09d-2-aarch64.pkg.tar.xz bash /tmp/r8s-installer/install.sh
systemd-analyze verify --man=no /etc/systemd/system/r8s-*.service /usr/lib/systemd/system/sddm.service
for so in /opt/mesa-g77/lib/libEGL_mesa.so.0 /opt/mesa-g77/lib/libvulkan_panfrost.so; do
  ldd "$so" | tee /tmp/mesa-ldd
  ! grep -q "not found" /tmp/mesa-ldd
done
tar -cf /results/desktop-configs.tar /etc/skel /usr/share/omarchy /usr/share/libalpm/hooks /usr/share/libalpm/scripts
pacman -Qi omarchy omarchy-settings hyprland quickshell > /results/desktop-package-info.txt
cp /tmp/pacman.conf /results/pacman.conf
pacman -Q > /results/installed-packages.txt
echo "PASS: ARM64 packages, installer, units and Mesa linking (hardware/session not tested)"
' 2>&1 | tee "$ROOT/logs/codex-arm64-userspace.log"
