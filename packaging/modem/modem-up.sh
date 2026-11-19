#!/bin/sh
# Bring the Shannon S5123 up to an enumerated PCIe endpoint (root, kernel with 0140-0142).
# Order from LineageOS cpif: power_on_cp() + SPI BOOT (cp-spiboot.sh), check_cp_status()
# (CP2AP_WAKEUP high), s5100_poweron_pcie() (AP2CP_WAKEUP, then RC power-on = relink).
set -eu
D=$(dirname "$0")
KEEP_CP_ON=1 sh "$D/cp-spiboot.sh" | grep -E "SPI:|ms "
[ "$(gpioget -b pull-down --numeric -c gpiochip51 0)" = 1 ] || { echo "CP2AP_WAKEUP baixo: boot do CP falhou"; sh "$D/modem-down.sh"; exit 1; }
gpioset -p 5ms -t 0 -c gpiochip12 3=1          # AP2CP_WAKEUP (gpg1-3)
echo 1 > /sys/bus/platform/devices/13d20000.pcie/relink
lspci -D -k -s 0001:01:00.0
