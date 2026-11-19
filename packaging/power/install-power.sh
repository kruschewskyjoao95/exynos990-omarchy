#!/bin/sh
# Install the r8s power profiles on the phone (root): power-profiles-daemon + r8s-power-profile.
set -eu
D=$(dirname "$(readlink -f "$0")")
pacman -S --noconfirm --needed power-profiles-daemon
install -d /usr/local/lib/r8s-power /etc/systemd/system/power-profiles-daemon.service.d
install -m 0755 "$D/r8s-power-profile.py" /usr/local/lib/r8s-power/
install -m 0644 "$D/r8s-fake-driver.conf" /etc/systemd/system/power-profiles-daemon.service.d/
install -m 0644 "$D/r8s-wifi-powersave.conf" /etc/NetworkManager/conf.d/zz-r8s-wifi-powersave.conf
install -m 0644 "$D/r8s-power-profile.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now power-profiles-daemon
echo "installed; start with: systemctl enable --now r8s-power-profile"
