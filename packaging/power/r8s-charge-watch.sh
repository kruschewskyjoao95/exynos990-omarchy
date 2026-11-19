#!/bin/sh
# Charging monitor for the r8s: samples the charger, battery and USB-C state once a second and writes a CSV plus
# a summary, so a charger or port can be tested while the phone is unplugged from the computer (no ssh needed).
#
#   r8s-charge-watch.sh [window_s] [max_s]      (root: it reads the typec debugfs)
#
# It logs from the start and stops `window_s` (default 240) seconds after the LAST time a source was connected
# (charger online going 0 -> 1), or after `max_s` (default 900) in total. Output: /var/tmp/charge-watch.csv and
# /var/tmp/charge-watch.summary. Read-only: it changes nothing on the phone.
WIN=${1:-240}
MAX=${2:-900}
CSV=/var/tmp/charge-watch.csv
SUM=/var/tmp/charge-watch.summary
B=/sys/class/power_supply/max170xx_battery
C=/sys/class/power_supply/max77705-charger
D=/sys/kernel/debug/max77705-typec/state
rd() { cat "$1" 2>/dev/null || echo -; }
field() { sed -n "s/^$1 \([0-9a-fA-F]*\).*/\1/p" "$D" 2>/dev/null | head -1; }
hexd() { [ -n "$1" ] && echo $((0x$1)) || echo -; }

echo "t_s,since_plug_s,online,status,soc_pct,batt_mV,batt_mA,batt_avg_mA,batt_temp_dC,in_limit_mA,chg_limit_mA,rp_istat,bc_chgtyp,pd_psrdy,pin,udc_state,udc_speed,soc_big_C,brightness" > $CSV
start=$(date +%s); last_online=0; plug_at=""; plugs=0

while :; do
	now=$(date +%s); t=$((now - start))
	online=$(rd $C/online)
	if [ "$online" = 1 ] && [ "$last_online" != 1 ]; then plug_at=$now; plugs=$((plugs + 1)); fi
	last_online=$online
	since=-; [ -n "$plug_at" ] && since=$((now - plug_at))

	cc=$(field cc_status0); bc=$(field bc_status); pd=$(field pd_status1)
	istat=-; chgtyp=-; psrdy=-; pin=-
	[ -n "$cc" ] && { istat=$(( (0x$cc >> 4) & 3 )); pin=$(( (0x$cc >> 6) & 3 )); }
	[ -n "$bc" ] && chgtyp=$(( 0x$bc & 3 ))
	[ -n "$pd" ] && psrdy=$(( (0x$pd >> 4) & 1 ))
	big=$(for z in /sys/class/thermal/thermal_zone*; do [ "$(cat $z/type 2>/dev/null)" = big-thermal ] && echo $(( $(cat $z/temp) / 1000 )); done)

	echo "$t,$since,$online,$(rd $B/status),$(rd $B/capacity),$(( $(rd $B/voltage_now) / 1000 )),$(( $(rd $B/current_now) / 1000 )),$(( $(rd $B/current_avg) / 1000 )),$(rd $B/temp),$(( $(rd $C/input_current_limit) / 1000 )),$(( $(rd $C/constant_charge_current) / 1000 )),$istat,$chgtyp,$psrdy,$pin,$(rd /sys/class/udc/*/state),$(rd /sys/class/udc/*/current_speed),${big:--},$(rd /sys/class/backlight/panel0-backlight/brightness)" >> $CSV

	[ -n "$plug_at" ] && [ $((now - plug_at)) -ge "$WIN" ] && break
	[ "$t" -ge "$MAX" ] && break
	sleep 1
done

# summary of the last window (rows with online=1 since the last plug)
{
	echo "r8s charge watch: $(date -u +%FT%TZ), $plugs plug event(s), ran $t s"
	awk -F, -v plug="${plug_at:-0}" 'NR>1 && $3==1 && $2 != "-" && $2 >= 0 {
		n++; i+=$7; v+=$6; if (min==""||$7<min) min=$7; if ($7>max||max=="") max=$7
		ist[$12]++; bc[$13]++; psr[$14]++; lim[$10]++; chg[$11]++; spd[$17]++; if ($18>tm) tm=$18; soc=$5; st[$4]++ }
	END {
		if (!n) { print "no samples with the charger online after the last plug"; exit }
		printf "samples online: %d, battery current mean %.0f mA (min %d, max %d; negative = discharging), mean %.0f mV\n", n, i/n, min, max, v/n
		printf "mean battery power %.2f W (negative = the battery is giving energy)\n", (i/n)*(v/n)/1e6
		printf "last SoC %s%%, hottest big-core zone %s C\n", soc, tm
		printf "battery status samples:"; for (k in st) printf " %s=%d", k, st[k]; print ""
		printf "source Rp ISTAT (0 none, 1 default USB, 2 1.5 A, 3 3 A):"; for (k in ist) printf " %s=%d", k, ist[k]; print ""
		printf "BC1.2 chgtyp (1 SDP, 2 CDP, 3 DCP):"; for (k in bc) printf " %s=%d", k, bc[k]; print ""
		printf "PD contract (psrdy):"; for (k in psr) printf " %s=%d", k, psr[k]; print ""
		printf "input limit mA:"; for (k in lim) printf " %s=%d", k, lim[k]; printf "  charge limit mA:"; for (k in chg) printf " %s=%d", k, chg[k]; print ""
		printf "USB speed:"; for (k in spd) printf " %s=%d", k, spd[k]; print ""
	}' $CSV
	echo "--- journal r8s-charge:"; journalctl -t r8s-charge --no-pager -n 6 -o cat 2>/dev/null
} > $SUM
