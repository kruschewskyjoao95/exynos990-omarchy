#!/bin/sh
# 1 Hz heartbeat into ramoops pmsg. After an auto-reboot the last seconds
# before a stall are preserved in /sys/fs/pstore/pmsg-ramoops-0.
C=/sys/devices/system/cpu
[ -c /dev/pmsg0 ] || exit 0
while :; do
  F=""
  for p in 0 4 6; do
    F="$F $(cat "$C/cpufreq/policy$p/scaling_cur_freq" 2>/dev/null || echo -)"
  done
  T=""
  for z in /sys/class/thermal/thermal_zone[1-4]; do
    [ -r "$z/temp" ] && T="$T $(( $(cat "$z/temp") / 1000 ))"
  done
  echo "hb $(cut -d' ' -f1 /proc/uptime) f:$F t:$T on:$(cat "$C/online" 2>/dev/null) ld:$(cut -d' ' -f1 /proc/loadavg)" > /dev/pmsg0 2>/dev/null || true
  sleep 1
done
