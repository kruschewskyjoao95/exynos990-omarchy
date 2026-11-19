#!/bin/sh
# Drop the modem PCIe link and power the S5123 off (power_off_cp(): reset low, then power low).
echo 0 > /sys/bus/platform/devices/13d20000.pcie/relink 2>/dev/null || true
gpioset -p 1ms -t 0 -c gpiochip12 3=0           # AP2CP_WAKEUP
gpioset -p 10ms -t 0 -c gpiochip30 0=0          # nreset
gpioset -p 10ms -t 0 -c gpiochip41 0=0          # cp_pwr_on
gpioset -p 1ms -t 0 -c gpiochip46 0=0           # pda_active
echo "modem desligado"
