#!/usr/bin/env bash
# Post-boot Omarchy installation recipe for r8s (Arch Linux ARM minimal base).
# Run ON THE S20 FE after booting the minimal Arch ARM rootfs and verifying
# r8s-growroot expanded /dev/sda32 (108 GiB) and Wi-Fi / USB networking is up.
#
# Never runs Omarchy's PC installer, disk partitioning, ISO setup, or Limine/GRUB.
set -euo pipefail

DRY_RUN=0
TARGET_USER="${R8S_USER:-r8s}"
OMARCHY_REPO_URL="${OMARCHY_REPO_URL:-https://pkgs.omarchy.org/stable/aarch64}"
KEYRING_PKG="${OMARCHY_KEYRING_PKG:-omarchy-keyring-20251027-1-any.pkg.tar.zst}"
KEYRING_SHA256="${OMARCHY_KEYRING_SHA256:-cce48c07cfc2b97e198df1bc81705db2921685032fe39f18b4ddfd84264b5967}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

log() { printf '== [omarchy-r8s] %s ==\n' "$*"; }

if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN: validating configuration for user=$TARGET_USER repo=$OMARCHY_REPO_URL"
  exit 0
fi

[ "$(id -u)" -eq 0 ] || { echo "must run as root (use sudo)" >&2; exit 1; }
id "$TARGET_USER" >/dev/null 2>&1 || { echo "user '$TARGET_USER' does not exist" >&2; exit 1; }

if systemctl is-active --quiet r8s-growroot.service 2>/dev/null; then
  echo "wait for r8s-growroot.service to finish expanding /dev/sda32 first" >&2
  exit 1
fi

AVAIL_MB=$(df -Pm / | awk 'NR==2 {print $4}')
if [ "${AVAIL_MB:-0}" -lt 4096 ]; then
  echo "ERROR: only ${AVAIL_MB} MiB free on /; confirm r8s-growroot expanded /dev/sda32 before installing desktop" >&2
  exit 1
fi

log "1. Configuring [omarchy] stable repo & IgnorePkg guards"
# Keep custom r8s kernel/firmware and PC bootloaders blocked from pacman updates.
if grep -q '^IgnorePkg' /etc/pacman.conf; then
  sed -i 's/^IgnorePkg.*/IgnorePkg = linux linux-aarch64 linux-aarch64-headers linux-firmware* limine* mkinitcpio*/' /etc/pacman.conf
else
  sed -i '/^\[options\]/a IgnorePkg = linux linux-aarch64 linux-aarch64-headers linux-firmware* limine* mkinitcpio*' /etc/pacman.conf
fi

# [omarchy] MUST precede [core] and [extra] so Omarchy's patched hyprland/quickshell win.
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
  awk -v url="$OMARCHY_REPO_URL" '
BEGIN { done = 0 }
/^\[core\]/ && !done {
  print "[omarchy]"
  print "SigLevel = Required DatabaseOptional"
  print "Server = " url
  print ""
  done = 1
}
{ print }
' /etc/pacman.conf > /etc/pacman.conf.new && mv /etc/pacman.conf.new /etc/pacman.conf
fi

log "2. Bootstrapping omarchy-keyring with SHA-256 verification"
TMP_KR=$(mktemp -d)
trap 'rm -rf "$TMP_KR"' EXIT
curl -fsSL "$OMARCHY_REPO_URL/$KEYRING_PKG" -o "$TMP_KR/$KEYRING_PKG"
echo "$KEYRING_SHA256  $TMP_KR/$KEYRING_PKG" | sha256sum -c -
pacman -U --noconfirm "$TMP_KR/$KEYRING_PKG"
pacman-key --populate omarchy

log "3. Syncing repositories & installing Omarchy + r8s desktop packages"
pacman -Syu --noconfirm
pacman -S --noconfirm --needed \
  omarchy \
  omarchy-settings \
  hyprland \
  quickshell \
  uwsm \
  sddm \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  mesa \
  libdrm \
  egl-wayland \
  foot \
  firefox \
  squeekboard \
  brightnessctl \
  xdg-user-dirs \
  xdg-utils \
  wl-clipboard \
  noto-fonts \
  noto-fonts-emoji

# Re-assert no generic kernel or PC bootloader slipped in.
if pacman -Q | grep -E '^(linux(-|$)|limine)' | grep -v '^linux-api-headers '; then
  echo "ERROR: forbidden kernel or PC bootloader package installed!" >&2
  exit 1
fi

log "4. Installing r8s DRM/Panfrost, fbcon, thermal, and display recovery glue"
cat > /usr/local/bin/r8s-detect-drm <<'EOF'
#!/bin/sh
# Detect exynos990 KMS card and Panfrost render/card nodes for Aquamarine/Hyprland.
DPU=""
PAN=""
for u in /sys/class/drm/card*/device/uevent; do
  [ -r "$u" ] || continue
  dev="/dev/dri/$(basename "$(dirname "$(dirname "$u")")")"
  if grep -q "exynos990" "$u" 2>/dev/null; then
    DPU="$dev"
  elif grep -qi "panfrost" "$u" 2>/dev/null; then
    PAN="$dev"
  fi
done
if [ -n "$DPU" ] && [ -n "$PAN" ]; then
  printf '%s:%s\n' "$DPU" "$PAN"
elif [ -n "$DPU" ]; then
  printf '%s\n' "$DPU"
fi
EOF
chmod 0755 /usr/local/bin/r8s-detect-drm

install -d /etc/profile.d /etc/environment.d
cat > /etc/profile.d/r8s-drm.sh <<'EOF'
export PAN_MESA_DEBUG=noafbc
if [ -x /usr/local/bin/r8s-detect-drm ]; then
  _r8s_drm=$(/usr/local/bin/r8s-detect-drm)
  [ -n "$_r8s_drm" ] && export AQ_DRM_DEVICES="$_r8s_drm"
  unset _r8s_drm
fi
EOF
cat > /etc/environment.d/90-r8s-drm.conf <<'EOF'
PAN_MESA_DEBUG=noafbc
EOF

# Unbind fbcon before display manager so exynos990-dpu DRM master is free.
cat > /usr/local/sbin/r8s-unbind-fbcon <<'EOF'
#!/bin/sh
for v in /sys/class/vtconsole/vtcon*/name; do
  [ -r "$v" ] || continue
  d=$(dirname "$v")
  if grep -qi "frame buffer" "$v" 2>/dev/null; then
    echo 0 > "$d/bind" 2>/dev/null || true
  fi
done
EOF
chmod 0755 /usr/local/sbin/r8s-unbind-fbcon

cat > /etc/systemd/system/r8s-unbind-fbcon.service <<'EOF'
[Unit]
Description=Unbind fbcon before Wayland display manager takes DRM master
Before=sddm.service display-manager.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/r8s-unbind-fbcon
[Install]
WantedBy=graphical.target
EOF

# Earlier thermal trip (70 C instead of 83 C stock) from port r8s-session.sh
cat > /usr/local/sbin/r8s-thermal-trip <<'EOF'
#!/bin/sh
for z in /sys/class/thermal/thermal_zone*; do
  [ -r "$z/type" ] || continue
  case "$(cat "$z/type" 2>/dev/null)" in
    big-thermal|mid-thermal|little-thermal)
      [ -w "$z/trip_point_0_temp" ] && echo 70000 > "$z/trip_point_0_temp" 2>/dev/null || true
      ;;
  esac
done
EOF
chmod 0755 /usr/local/sbin/r8s-thermal-trip

cat > /etc/systemd/system/r8s-thermal-trip.service <<'EOF'
[Unit]
Description=r8s conservative 70C passive thermal trip
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/r8s-thermal-trip
[Install]
WantedBy=multi-user.target
EOF

# Visible console fallback if SDDM/graphical session fails
cat > /usr/local/sbin/r8s-recovery-vt <<'EOF'
#!/bin/sh
for v in /sys/class/vtconsole/vtcon*/name; do
  [ -r "$v" ] || continue
  d=$(dirname "$v")
  grep -qi "frame buffer" "$v" 2>/dev/null && echo 1 > "$d/bind" 2>/dev/null || true
done
systemctl start getty@tty1.service 2>/dev/null || true
logger -t r8s-recovery "Graphical session failed; tty1 console rebound"
EOF
chmod 0755 /usr/local/sbin/r8s-recovery-vt

cat > /etc/systemd/system/r8s-recovery-vt.service <<'EOF'
[Unit]
Description=Rebind framebuffer console if display manager fails
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/r8s-recovery-vt
EOF

install -d /etc/systemd/system/sddm.service.d
cat > /etc/systemd/system/sddm.service.d/10-r8s.conf <<'EOF'
[Unit]
After=r8s-unbind-fbcon.service
Wants=r8s-unbind-fbcon.service
OnFailure=r8s-recovery-vt.service
EOF

log "5. Provisioning /etc/skel Omarchy configs & r8s touch/display overrides for $TARGET_USER"
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
cp -a /etc/skel/. "$USER_HOME/"

install -d "$USER_HOME/.config/hypr" "$USER_HOME/.config/uwsm"
cat > "$USER_HOME/.config/uwsm/env" <<'EOF'
export PAN_MESA_DEBUG=noafbc
if [ -x /usr/local/bin/r8s-detect-drm ]; then
  _r8s_drm=$(/usr/local/bin/r8s-detect-drm)
  [ -n "$_r8s_drm" ] && export AQ_DRM_DEVICES="$_r8s_drm"
  unset _r8s_drm
fi
EOF

cat > "$USER_HOME/.config/hypr/monitors.lua" <<'EOF'
-- Samsung Galaxy S20 FE internal panel (1080x2400 portrait).
hl.monitor({ output = "DSI-1", mode = "1080x2400@60", position = "0x0", scale = 2 })
hl.env("GDK_SCALE", "2")
EOF

cat > "$USER_HOME/.config/hypr/autostart.lua" <<'EOF'
-- Launch squeekboard on-screen keyboard for touch-first use on r8s.
hl.on("hyprland.start", function()
  hl.exec_cmd(o.launch("squeekboard"))
end)
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME"
chmod 0700 "$USER_HOME/.ssh"
chmod 0600 "$USER_HOME/.ssh/authorized_keys"

log "6. Enabling display manager and r8s services"
systemctl enable r8s-thermal-trip.service r8s-unbind-fbcon.service sddm.service
systemctl set-default graphical.target

log "DONE. Reboot and verify renderer (must be Mali-G77/Panfrost, never llvmpipe)."
