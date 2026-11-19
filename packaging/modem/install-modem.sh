#!/bin/sh
# Install the r8s modem service from a checkout of packaging/modem (root, on the phone).
# Needs cuse-umts and cbd-props.so built on the phone (see their headers); the vendor cbd stays in
# the phone's own vendor partition and is never copied.
set -eu
D=$(dirname "$(readlink -f "$0")")
L=/usr/local/lib/r8s-modem
install -d $L
for f in s5123-ril.py ipc-handshake.py s5123-modem-run.sh modem-down.sh cp-spiboot.sh; do
	install -m 0755 "$D/$f" $L/
done
[ -x "$D/cuse-umts" ] && install -m 0755 "$D/cuse-umts" $L/
[ -f "$D/cbd-props.so" ] && install -m 0644 "$D/cbd-props.so" $L/
install -m 0644 "$D/r8s-modem.service" /etc/systemd/system/r8s-modem.service
systemctl daemon-reload
echo "installed; start with: systemctl enable --now r8s-modem"
