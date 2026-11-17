#!/usr/bin/env bash
# Post-boot Omarchy installation recipe for r8s (Arch Linux ARM minimal base).
# Run ON THE S20 FE after booting the minimal Arch ARM rootfs and verifying
# r8s-growroot expanded /dev/sda32 (108 GiB) and Wi-Fi / USB networking is up.
#
# Never runs Omarchy's PC installer, disk partitioning, ISO setup, or Limine/GRUB.
set -euo pipefail

DRY_RUN=0
ALLOW_STOCK_MESA="${R8S_ALLOW_STOCK_MESA:-0}"
MESA_G77_PKG="${R8S_MESA_G77_PKG:-}"
SDDM_AUTOLOGIN="${R8S_SDDM_AUTOLOGIN:-1}"
TARGET_USER="${R8S_USER:-r8s}"
OMARCHY_REPO_URL="${OMARCHY_REPO_URL:-https://pkgs.omarchy.org/stable/aarch64}"
KEYRING_PKG="${OMARCHY_KEYRING_PKG:-omarchy-keyring-20251027-1-any.pkg.tar.zst}"
KEYRING_SHA256="${OMARCHY_KEYRING_SHA256:-cce48c07cfc2b97e198df1bc81705db2921685032fe39f18b4ddfd84264b5967}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --allow-stock-mesa) ALLOW_STOCK_MESA=1 ;;
    *) echo "usage: $0 [--dry-run] [--allow-stock-mesa]" >&2; exit 2 ;;
  esac
done

log() { printf '== [omarchy-r8s] %s ==\n' "$*"; }

# Strip any previous BEGIN..END block and append the new block from stdin.
upsert_marked_block() {
  local file=$1 begin=$2 end=$3
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    awk -v b="$begin" -v e="$end" '
      $0 == b { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$file" > "${file}.tmp.$$"
    mv "${file}.tmp.$$" "$file"
  else
    : > "$file"
  fi
  {
    printf '%s\n' "$begin"
    cat
    printf '%s\n' "$end"
  } >> "$file"
}

if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN: user=$TARGET_USER repo=$OMARCHY_REPO_URL sddm_autologin=$SDDM_AUTOLOGIN allow_stock_mesa=$ALLOW_STOCK_MESA mesa_g77_pkg=${MESA_G77_PKG:-none}"
  log "Preview only: target hardware and package installation are not validated."
  exit 0
fi

[ "$(uname -m)" = aarch64 ] || { echo "ERROR: this installer requires aarch64 r8s" >&2; exit 1; }
if [ ! -r /sys/firmware/devicetree/base/compatible ] ||
   ! tr '\0' '\n' < /sys/firmware/devicetree/base/compatible | grep -Fxq 'samsung,r8s'; then
  echo "ERROR: this installer requires the samsung,r8s device tree" >&2
  exit 1
fi
if [ ! -r /etc/os-release ] || ! grep -Eq '^ID="?archarm"?$' /etc/os-release; then
  echo "ERROR: this installer requires the Arch Linux ARM rootfs" >&2
  exit 1
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

if [ -n "$MESA_G77_PKG" ] && [ ! -f "$MESA_G77_PKG" ]; then
  echo "ERROR: R8S_MESA_G77_PKG file not found: $MESA_G77_PKG" >&2
  exit 1
fi
if [ -z "$MESA_G77_PKG" ] && [ ! -d /opt/mesa-g77 ] && [ "$ALLOW_STOCK_MESA" != "1" ]; then
  echo "ERROR: /opt/mesa-g77 (patched Mali-G77/Panfrost Mesa) is not installed." >&2
  echo "Build & install packaging/mesa-g77/PKGBUILD (or pass R8S_MESA_G77_PKG=/path/to/mesa-g77-*.pkg.tar.zst)." >&2
  echo "For non-accelerated diagnostic bring-up only, re-run with --allow-stock-mesa (R8S_ALLOW_STOCK_MESA=1)." >&2
  exit 1
fi

log "1. Configuring [omarchy] stable repo & IgnorePkg guards"
# Keep custom r8s kernel/firmware and PC bootloaders blocked from pacman updates.
IGNORE_LIST="linux linux-aarch64 linux-aarch64-headers linux-firmware* limine* mkinitcpio*"
if grep -q '^IgnorePkg' /etc/pacman.conf; then
  sed -i "s/^IgnorePkg.*/IgnorePkg = $IGNORE_LIST/" /etc/pacman.conf
elif grep -q '^#IgnorePkg' /etc/pacman.conf; then
  sed -i "s/^#IgnorePkg.*/IgnorePkg = $IGNORE_LIST/" /etc/pacman.conf
else
  sed -i "/^\[options\]/a IgnorePkg = $IGNORE_LIST" /etc/pacman.conf
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
# Note: extra/mesa satisfies pacman SONAME dependencies (hyprland, qt6-base, egl-wayland),
# while patched r8s Mali-G77 Mesa lives side-by-side in /opt/mesa-g77 (packaging/mesa-g77/).
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

if [ -n "$MESA_G77_PKG" ]; then
  log "3b. Installing side-by-side /opt/mesa-g77 package ($MESA_G77_PKG)"
  pacman -U --noconfirm "$MESA_G77_PKG"
fi

# Re-assert no generic kernel or PC bootloader slipped in.
if pacman -Q | grep -E '^(linux(-|$)|limine)' | grep -v '^linux-api-headers '; then
  echo "ERROR: forbidden kernel or PC bootloader package installed!" >&2
  exit 1
fi

log "4. Installing r8s DRM/Panfrost, PipeWire null sink, fbcon, thermal, SDDM & power glue"
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

cat > /usr/local/sbin/r8s-write-drm-env <<'EOF'
#!/bin/sh
# Populate /run/r8s-drm.env for display-manager (SDDM) and system Wayland services
# that do not inherit /etc/profile.d or ~/.config/uwsm/env.
set -eu

OUT=/run/r8s-drm.env
TMP="${OUT}.tmp.$$"

{
  printf 'PAN_MESA_DEBUG=noafbc\n'
  if [ -x /usr/local/bin/r8s-detect-drm ]; then
    drm=$(/usr/local/bin/r8s-detect-drm || true)
    [ -n "$drm" ] && printf 'AQ_DRM_DEVICES=%s\n' "$drm"
  fi
  if [ -d /opt/mesa-g77 ]; then
    printf 'LD_LIBRARY_PATH=/opt/mesa-g77/lib\n'
    printf '__EGL_VENDOR_LIBRARY_FILENAMES=/opt/mesa-g77/share/glvnd/egl_vendor.d/50_mesa.json\n'
    printf 'LIBGL_DRIVERS_PATH=/opt/mesa-g77/lib/dri\n'
    printf 'GBM_BACKENDS_PATH=/opt/mesa-g77/lib/gbm\n'
    printf 'VK_DRIVER_FILES=/opt/mesa-g77/share/vulkan/icd.d/panfrost_icd.aarch64.json\n'
    printf 'VK_ICD_FILENAMES=/opt/mesa-g77/share/vulkan/icd.d/panfrost_icd.aarch64.json\n'
    printf 'PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1\n'
  fi
} > "$TMP"

chmod 0644 "$TMP"
mv "$TMP" "$OUT"
EOF
chmod 0755 /usr/local/sbin/r8s-write-drm-env

install -d /etc/profile.d /etc/environment.d
cat > /etc/profile.d/r8s-drm.sh <<'EOF'
[ -r /etc/profile.d/r8s-mesa-g77.sh ] && . /etc/profile.d/r8s-mesa-g77.sh
export PAN_MESA_DEBUG="${PAN_MESA_DEBUG:-noafbc}"
if [ -x /usr/local/bin/r8s-detect-drm ]; then
  _r8s_drm=$(/usr/local/bin/r8s-detect-drm)
  [ -n "$_r8s_drm" ] && export AQ_DRM_DEVICES="$_r8s_drm"
  unset _r8s_drm
fi
EOF
cat > /etc/environment.d/90-r8s-drm.conf <<'EOF'
PAN_MESA_DEBUG=noafbc
EOF

# PipeWire null sink so audio-enumerating apps do not abort while Exynos ABOX has no driver.
install -d /etc/pipewire/pipewire.conf.d
cat > /etc/pipewire/pipewire.conf.d/10-null-sink.conf <<'EOF'
context.objects = [
    {   factory = adapter
        args = {
            factory.name          = support.null-audio-sink
            node.name             = "r8s-silent-output"
            node.description      = "Phone Output (no audio device connected)"
            media.class           = Audio/Sink
            audio.position        = [ FL FR ]
            audio.rate            = 48000
            monitor.channel-volumes = true
            priority.session      = 100
            priority.driver       = 100
        }
    }
]
EOF

# Never apply the labwc 90-degree udev touch rotation matrix under Hyprland portrait mode
# (or Hyprland output-mapped touch, which would double-rotate).
rm -f /etc/udev/rules.d/91-r8s-touch-rotate.rules
install -d /etc/udev/rules.d
cat > /etc/udev/rules.d/91-r8s-touch-rotate.disabled <<'EOF'
# Disabled for Arch + Hyprland:
# The Zinitix ZT7650 panel/touch native resolution is 1080x2400 portrait, matching
# DSI-1 (no transform). Moreover, Hyprland applies output transforms to mapped
# touch devices (input:touchdevice:output = DSI-1), so adding a udev
# LIBINPUT_CALIBRATION_MATRIX here would misalign or double-rotate touch input.
EOF

# Power-key semantics: logind keeps 5s HandlePowerKeyLongPress=poweroff with
# PowerKeyIgnoreInhibited=yes as a kernel/logind safety net, while Hyprland handles
# short presses via r8s-power-action.
install -d /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-r8s.conf <<'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
PowerKeyIgnoreInhibited=yes
HoldoffTimeoutSec=10s
EOF

cat > /usr/local/bin/r8s-power-action <<'EOF'
#!/bin/sh
# Power-key action for Omarchy/Hyprland on r8s.
# Invoked by Hyprland bindl on XF86PowerOff (logind keeps 5s HandlePowerKeyLongPress=poweroff).
set -u

ACTION="${1:-short}"

if ! command -v hyprctl >/dev/null 2>&1; then
  logger -t r8s-power "hyprctl not found for action=$ACTION"
  exit 0
fi

case "$ACTION" in
  short)
    if hyprctl -j monitors 2>/dev/null | grep -q '"dpmsStatus":[[:space:]]*false'; then
      hyprctl dispatch dpms on >/dev/null 2>&1 || true
    else
      if command -v omarchy-lock-screen >/dev/null 2>&1; then
        omarchy-lock-screen >/dev/null 2>&1 &
      fi
      hyprctl dispatch dpms off >/dev/null 2>&1 || true
    fi
    ;;
  menu)
    if command -v omarchy-menu >/dev/null 2>&1; then
      exec omarchy-menu system
    fi
    ;;
  *)
    echo "usage: $0 [short|menu]" >&2
    exit 2
    ;;
esac
EOF
chmod 0755 /usr/local/bin/r8s-power-action

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
[Service]
ExecStartPre=/usr/local/sbin/r8s-write-drm-env
EnvironmentFile=-/run/r8s-drm.env
EOF

# Configure SDDM Wayland greeter and touch-safe autologin (squeekboard starts inside Hyprland;
# disabling R8S_SDDM_AUTOLOGIN=1 requires a greeter OSK or USB keyboard).
install -d /etc/sddm.conf.d
SESSION_DESKTOP="hyprland.desktop"
if [ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ]; then
  SESSION_DESKTOP="hyprland-uwsm.desktop"
fi
if [ "$SDDM_AUTOLOGIN" = "1" ]; then
  cat > /etc/sddm.conf.d/10-r8s.conf <<EOF
[General]
DisplayServer=wayland

[Autologin]
User=$TARGET_USER
Session=$SESSION_DESKTOP
Relogin=false
EOF
else
  cat > /etc/sddm.conf.d/10-r8s.conf <<EOF
[General]
DisplayServer=wayland
EOF
fi

log "5. Provisioning /etc/skel Omarchy configs & r8s touch/display/power overrides for $TARGET_USER"
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
cp -a /etc/skel/. "$USER_HOME/"

install -d "$USER_HOME/.config/hypr" "$USER_HOME/.config/uwsm"
upsert_marked_block "$USER_HOME/.config/uwsm/env" "# BEGIN r8s" "# END r8s" <<'EOF'
[ -r /etc/profile.d/r8s-mesa-g77.sh ] && . /etc/profile.d/r8s-mesa-g77.sh
export PAN_MESA_DEBUG="${PAN_MESA_DEBUG:-noafbc}"
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

upsert_marked_block "$USER_HOME/.config/hypr/autostart.lua" "-- BEGIN r8s" "-- END r8s" <<'EOF'
-- Touch mapping, OSK, and short-press power key handling for r8s.
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl keyword input:touchdevice:output DSI-1")
  hl.exec_cmd("hyprctl keyword input:touchdevice:transform -1")
  hl.exec_cmd("hyprctl keyword bindl ', XF86PowerOff, exec, /usr/local/bin/r8s-power-action short'")
  hl.exec_cmd("hyprctl keyword bindl 'SHIFT, XF86PowerOff, exec, /usr/local/bin/r8s-power-action menu'")
  hl.exec_cmd(o.launch("squeekboard"))
end)
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME"
[ -d "$USER_HOME/.ssh" ] && chmod 0700 "$USER_HOME/.ssh"
[ -f "$USER_HOME/.ssh/authorized_keys" ] && chmod 0600 "$USER_HOME/.ssh/authorized_keys"

log "6. Enabling display manager and r8s services"
systemctl enable r8s-thermal-trip.service r8s-unbind-fbcon.service sddm.service
systemctl set-default graphical.target

log "DONE. Reboot and verify renderer (must be Mali-G77/Panfrost via /opt/mesa-g77, never llvmpipe)."
