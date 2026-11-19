#!/usr/bin/env python3
"""r8s power profiles: follow power-profiles-daemon (the Omarchy battery menu) and apply, per profile,
a screen brightness and one fixed CPU frequency per cluster. Root, systemd service r8s-power-profile.

CPU: the three clusters stay pinned (scaling_min_freq == scaling_max_freq), as r8s-safe-freq does, and a
profile change moves each pin once, one cluster at a time. Unlocking cpufreq ("dyn") is the mode in which the
ACPM DVFS mailbox timed out (-110) and hung a core (see sources/port/device/r8s-safe-freq), so it is not used.
GPU: this kernel has no devfreq for the Mali (fixed-clock stub), so no profile can change its frequency.
"""
import os, sys, syslog, time

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

CPUFREQ = "/sys/devices/system/cpu/cpufreq"
BACKLIGHT = "/sys/class/backlight/panel0-backlight"
CLUSTER_ORDER = ("policy0", "policy4", "policy6")        # little, mid, big (M5): little first
SETTLE_S = 0.5

# kHz, all in each cluster's table (scaling_available_frequencies); "balanced" is r8s-safe-freq's pin.
#
# wifi_ps: Wi-Fi power save, measured at ~60-70 mA on this phone (-350 mA off, -287 mA on); on except Performance.
# The thermal trip stays at r8s-thermal-trip's 70 C for every profile: moving it per profile left a cluster
# stuck at its lowest frequency (the zone only releases 5 C below the trip), seen on the big cluster.
# charge_ua: ceiling for the battery charge current (uA), applied through r8s-charge-limit.sh together with what the
# source offers (the lower one wins). Charging heats the phone: 2 A raised the big-core zone 59 -> 68 C in 4 minutes.
PROFILES = {
    "power-saver": {"brightness": 30, "wifi_ps": True, "charge_ua": 1000000,
                    "cpu": {"policy0": 806000, "policy4": 845000, "policy6": 858000}},
    "balanced": {"brightness": 50, "wifi_ps": True, "charge_ua": 2000000,
                 "cpu": {"policy0": 1456000, "policy4": 1690000, "policy6": 1586000}},
    "performance": {"brightness": 80, "wifi_ps": False, "charge_ua": 2000000,
                    "cpu": {"policy0": 1846000, "policy4": 2210000, "policy6": 1794000}},
}


def log(msg):
    syslog.syslog(msg)
    print(msg, flush=True)


def rd(path):
    with open(path) as f:
        return f.read().strip()


def wr(path, value):
    with open(path, "w") as f:
        f.write(str(value))


def set_brightness(percent):
    top = int(rd(BACKLIGHT + "/max_brightness"))
    wr(BACKLIGHT + "/brightness", max(1, round(top * percent / 100)))


def set_wifi_powersave(on):
    import subprocess
    out = subprocess.run(["iw", "dev"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.strip().startswith("Interface"):
            subprocess.run(["iw", "dev", line.split()[1], "set", "power_save", "on" if on else "off"])


def set_charge_cap(ua):
    """Leave the ceiling for r8s-charge-limit.sh and re-apply it now if a charger is connected."""
    import subprocess
    try:
        wr("/run/r8s-charge-cap", ua)
    except OSError as e:
        return log("charge cap: %s" % e)
    if os.path.exists("/usr/local/bin/r8s-charge-limit.sh"):
        subprocess.run(["/usr/local/bin/r8s-charge-limit.sh"])


def dmesg_errors():
    """Count of ACPM/cpufreq failures in the kernel log, to notice a bad step before the next one."""
    import subprocess
    out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
    return sum(1 for l in out.splitlines() if ("ACPM" in l or "cpufreq" in l) and ("-110" in l or "timed out" in l))


def pin(policy, khz):
    """Move one cluster's pin: raising writes max then min, lowering writes min then max, so the range is
    never empty and cpufreq makes a single transition."""
    base = "%s/%s" % (CPUFREQ, policy)
    if not os.path.isdir(base):
        return True
    if khz not in [int(x) for x in rd(base + "/scaling_available_frequencies").split()]:
        log("%s: %d kHz is not in the table, skipped" % (policy, khz))
        return True
    cur = int(rd(base + "/scaling_max_freq"))
    if cur == khz and int(rd(base + "/scaling_min_freq")) == khz:
        return True
    first, second = ("scaling_max_freq", "scaling_min_freq") if khz > cur else ("scaling_min_freq", "scaling_max_freq")
    before = dmesg_errors()
    wr("%s/%s" % (base, first), khz)
    wr("%s/%s" % (base, second), khz)
    time.sleep(SETTLE_S)
    now = int(rd(base + "/scaling_cur_freq"))
    errors = dmesg_errors() - before
    log("%s -> %d kHz (now %d kHz, %d new ACPM errors)" % (policy, khz, now, errors))
    return errors == 0


current = None


def apply(profile):
    global current
    if profile == current or profile not in PROFILES:
        return
    cfg = PROFILES[profile]
    log("profile %s: brightness %d%%, wifi power save %s, cpu %s" % (
        profile, cfg["brightness"], cfg["wifi_ps"], cfg["cpu"]))
    try:
        set_brightness(cfg["brightness"])
    except OSError as e:
        log("brightness: %s" % e)
    set_wifi_powersave(cfg["wifi_ps"])
    set_charge_cap(cfg["charge_ua"])
    for policy in CLUSTER_ORDER:
        if not pin(policy, cfg["cpu"][policy]):
            log("ACPM errors after %s: stopping here, the other clusters keep their last pin" % policy)
            break
    current = profile


def main():
    syslog.openlog("r8s-power-profile")
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    proxy = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None, "org.freedesktop.UPower.PowerProfiles",
                                   "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", None)

    def active():
        v = proxy.get_cached_property("ActiveProfile")
        return v.get_string() if v else None

    proxy.connect("g-properties-changed", lambda *_: apply(active()))
    apply(active())
    GLib.MainLoop().run()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--check":          # self-check without touching the phone
        for name, cfg in PROFILES.items():
            assert 0 < cfg["brightness"] <= 100 and set(cfg["cpu"]) == set(CLUSTER_ORDER), name
            assert isinstance(cfg["wifi_ps"], bool) and 500000 <= cfg["charge_ua"] <= 2000000, name
        assert [p["brightness"] for p in PROFILES.values()] == [30, 50, 80]
        print("ok")
        sys.exit(0)
    main()
