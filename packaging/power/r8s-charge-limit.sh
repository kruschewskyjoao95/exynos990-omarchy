#!/bin/sh
# Charger input policy, run by udev when the max77705 charger changes (90-r8s-charge-limit.rules).
#
# The max77705 defaults to 900 mA on any 5 V source, which cannot cover the SoC under load (battery drained
# 91% -> 59% "charging" on a Mac USB port with the E1 spinners). So the limit is raised to what the source
# advertises on the CC pins (Rp, USB-C spec: default 0.5/0.9 A, 1.5 A, 3 A), read from the typec driver's
# debugfs (cc_status0 bits 5:4 = ISTAT). The charger's AICL still backs off on a source that sags.
#
# No USB Power Delivery is negotiated here (psrdy stays 0: the driver only follows the PMIC firmware), so the
# phone stays at 5 V: at most 3 A = 15 W with a 3 A source, 7.5 W with 1.5 A, about 4.5 W on a default port.
C=/sys/class/power_supply/max77705-charger
D=/sys/kernel/debug/max77705-typec/state
[ "$(cat $C/online 2>/dev/null)" = 1 ] || exit 0

istat=$(sed -n 's/^cc_status0 \([0-9a-fA-F]*\)/\1/p' $D 2>/dev/null)
bc=$(sed -n 's/^bc_status \([0-9a-fA-F]*\)/\1/p' $D 2>/dev/null)
if [ -n "$istat" ]; then
	istat=$(( (0x$istat >> 4) & 3 ))
	chgtyp=$(( 0x${bc:-0} & 3 ))
else
	istat=-1 chgtyp=-1                      # debugfs unavailable: keep the previous policy
fi

case $istat in
	3) in_ua=3000000; chg_ua=2000000 ;;     # source offers 3 A
	*) in_ua=1500000; chg_ua=1500000 ;;     # 1.5 A, default or unknown: as before, AICL protects
esac
# The power profile (r8s-power-profile) leaves a charge-current ceiling in CAP: Power saver charges slower so the
# phone stays cooler (2 A raised the big-core zone from 59 to 68 C in 4 minutes with the screen on).
CAP=/run/r8s-charge-cap
cap=none
[ -r $CAP ] && cap=$(cat $CAP) && [ "$cap" -gt 0 ] 2>/dev/null && [ "$cap" -lt "$chg_ua" ] && chg_ua=$cap
echo $in_ua > $C/input_current_limit 2>/dev/null
echo $chg_ua > $C/constant_charge_current 2>/dev/null
logger -t r8s-charge "source Rp ISTAT=$istat chgtyp=$chgtyp, profile cap $cap: input limit $(cat $C/input_current_limit) uA, charge $(cat $C/constant_charge_current) uA"
