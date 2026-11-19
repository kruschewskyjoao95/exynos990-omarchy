#!/usr/bin/env python3
# Runs on the phone as root, after `KEEP_CP_ON=1 sh cp-spiboot.sh` left the
# S5123 bootloader running. Milestone 3 prototype: bring up the Exynos 990
# PCIe GEN4_1 root complex (channel 1, the modem link) from userspace and
# report whether LTSSM reaches L0. Mirrors LineageOS 97369af7
# pcie-exynos-rc.c exynos_pcie_rc_poweron()/establish_link() and
# pcie-exynos9830-rc-cal.c exynos_pcie_rc_pcie_phy_config() for chip_ver 1
# (&pcie_2 chip-ver = <1> in exynos990-r8s_eur_open_05.dts).
# shortcut: register pokes through /dev/mem, upgrade to a pci-exynos.c GEN4 path once L0 is proven.
# WARNING (19/11/2026): on r8s kernel #13 the first ELBI read (0x13D202C8) hangs the SoC
# (hard lockup, watchdog reboot) even with all CMU_HSI2 gates/QCH on. Do not run until the
# missing enable (reset/isolation/TZPC) is found; see checks/modem-s5123.md.
import mmap, os, struct, subprocess, sys, time

ELBI, PHY, SYSREG, DBI, PCS = 0x13D20000, 0x13D50000, 0x13C20000, 0x13800000, 0x13D40000
PMU, PINCTRL_HSI2 = 0x15860000, 0x13C30000
PMU_PCIE1_PHY = 0x720           # pmu-offset of pcie_2, bit 0 = PHY isolation bypass

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
maps = {}
def mm(base, size=0x2000):
    if base not in maps:
        maps[base] = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
    return maps[base]
def rd(base, off): return struct.unpack_from("<I", mm(base), off)[0]
def wr(base, off, val): struct.pack_into("<I", mm(base), off, val)
def ms(t): time.sleep(t / 1000)

def gpio(line, val):
    subprocess.run(["gpioset", "-p", "1ms", "-t", "0", "-c", "gpiochip19", f"{line}={val}"], check=True)

LTSSM = {0x00: "DETECT_QUIET", 0x01: "DETECT_ACT", 0x02: "POLL_ACTIVE", 0x03: "POLL_COMPLIANCE",
         0x04: "POLL_CONFIG", 0x06: "CFG_LINKWD_START", 0x07: "CFG_LINKWD_ACEPT", 0x08: "CFG_LANENUM_WAIT",
         0x09: "CFG_LANENUM_ACEPT", 0x0a: "CFG_COMPLETE", 0x0b: "CFG_IDLE", 0x0c: "RCVRY_LOCK",
         0x0d: "RCVRY_SPEED", 0x0e: "RCVRY_RCVRCFG", 0x0f: "RCVRY_IDLE", 0x10: "L0", 0x11: "L0 (Samsung linkup)",
         0x12: "L0S", 0x13: "L123_SEND_EIDLE", 0x14: "L1_IDLE", 0x15: "L2_IDLE", 0x16: "L2_WAKE",
         0x17: "DISABLED_ENTRY", 0x19: "DISABLED", 0x1a: "LPBK_ENTRY", 0x1e: "LPBK_EXIT", 0x20: "HOT_RESET"}

def phy_config():
    # PCS&PHY INIT_RST, PHY PORT_RST, PHY CMN_RST pulses
    for reg in (0x1404, 0x1400, 0x1408):
        wr(ELBI, reg, 1); time.sleep(0.00001); wr(ELBI, reg, 0); ms(1)
    wr(PHY, 0xD8, 0x28)          # input clk path change init
    for off, val in [  # chip_ver == 1 (EVT1 GEN4 PHY)
        (0x18, 0x50), (0x48, 0x33), (0x68, 0x01), (0x70, 0x12), (0x78, 0x7F), (0x84, 0x0A), (0x88, 0x58),
        (0x8C, 0x00), (0x90, 0x21), (0x104, 0xB6), (0x458, 0x06), (0x550, 0x38), (0x5B0, 0x34),
        (0x8D0, 0x01), (0x8F4, 0x30), (0x90C, 0x60), (0x9B4, 0x06), (0x9C0, 0x3F), (0x9C4, 0xFB),
        (0xA6C, 0x03), (0xB40, 0x06), (0xB44, 0x06), (0xB48, 0x06), (0xB4C, 0x06), (0xB50, 0x00),
        (0xB54, 0x00), (0xB58, 0x00), (0xB5C, 0x03), (0xC44, 0x16), (0xC48, 0x16), (0xC4C, 0x16),
        (0xC50, 0x16), (0xC54, 0x0A), (0xC58, 0x0A), (0xC5C, 0x0A), (0xC60, 0x0A), (0xC64, 0x08),
        (0xC68, 0x08), (0xC6C, 0x02), (0xC70, 0x0A), (0xCA8, 0xE7), (0xCAC, 0x00), (0xCB0, 0x0E),
        (0xCCC, 0x1C), (0xCD4, 0x05), (0xCD8, 0x77), (0xCDC, 0x7A), (0xDB4, 0x2F), (0x15B4, 0x2F),
        (0x10D0, 0x01), (0x10F4, 0x30), (0x110C, 0x60), (0x11B4, 0x06), (0x11C0, 0x3F), (0x11C4, 0xFB),
        (0x126C, 0x03), (0x1340, 0x06), (0x1344, 0x06), (0x1348, 0x06), (0x134C, 0x06), (0x1350, 0x00),
        (0x1354, 0x00), (0x1358, 0x00), (0x135C, 0x03), (0x1444, 0x16), (0x1448, 0x16), (0x144C, 0x16),
        (0x1450, 0x16), (0x1454, 0x0A), (0x1458, 0x0A), (0x145C, 0x0A), (0x1460, 0x0A), (0x1464, 0x08),
        (0x1468, 0x08), (0x146C, 0x02), (0x1470, 0x0A), (0x14A8, 0xE7), (0x14AC, 0x00), (0x14B0, 0x0E),
        (0x14CC, 0x1C), (0x14D4, 0x05), (0x14D8, 0x77), (0x14DC, 0x7A),
        # for Gen4 0709
        (0xC70, 0x00), (0xCA8, 0xE7), (0xCAC, 0x00), (0xCB0, 0x0A), (0x9B4, 0xC0), (0xA6C, 0x01),
        (0xBA8, 0x01), (0xC08, 0x04), (0xC40, 0x06), (0xB4C, 0x04),
        (0x1470, 0x00), (0x14A8, 0xE7), (0x14AC, 0x00), (0x14B0, 0x0A), (0x11B4, 0xC0), (0x126C, 0x01),
        (0x13A8, 0x01), (0x1408, 0x04), (0x1440, 0x06), (0x134C, 0x04),
        (0x450, 0x20), (0x908, 0x05), (0x1108, 0x05), (0x840, 0x10), (0x1040, 0x10),
        (0x82C, 0x08), (0x102C, 0x08),
        (0x550, 0x00),               # AES disable
        (0xB9C, 0x01), (0x139C, 0x01),  # DFE off
    ]:
        wr(PHY, off, val)
    wr(ELBI, 0x1400, 1); ms(1)   # PHY PORT_RST
    wr(PCS, 0x154, 0x700D5); wr(PCS, 0x954, 0x700D5)
    wr(PCS, 0x150, 0x300FF)      # GEN4 PHY: for L2 power

def power_down():
    wr(ELBI, 0x54, 0)            # LTSSM disable
    gpio(1, 0)                   # PERST assert
    v = rd(SYSREG, 0x800); wr(SYSREG, 0x800, (v & ~(1 << 5)) | (1 << 4))
    wr(PHY, 0x400, 0x23)         # PHY all power down
    wr(PMU, PMU_PCIE1_PHY, rd(PMU, PMU_PCIE1_PHY) & ~1)

# CLKREQ gpf3-0: function 2, pull-up, drive 3 (LineageOS pcie2_clkreq); PERST gpf3-1 output low.
con = rd(PINCTRL_HSI2, 0x0); wr(PINCTRL_HSI2, 0x0, (con & ~0xf) | 0x2)
pud = rd(PINCTRL_HSI2, 0x8); wr(PINCTRL_HSI2, 0x8, (pud & ~0xf) | 0x3)
drv = rd(PINCTRL_HSI2, 0xc); wr(PINCTRL_HSI2, 0xc, (drv & ~0xff) | 0x33)
gpio(1, 0)

try:
    print("antes: pmu=%#x ltssm=%#x" % (rd(PMU, PMU_PCIE1_PHY), rd(ELBI, 0x2C8) & 0x3f))
    wr(PMU, PMU_PCIE1_PHY, rd(PMU, PMU_PCIE1_PHY) | 1)   # PHY isolation bypass
    wr(PHY, 0x400, 0x0)                                   # PHY all power down clear
    wr(PCS, 0x180, 0x0D)                                  # force_pclk_en
    phy_config()
    v = rd(ELBI, 0x3A4); wr(ELBI, 0x3A4, v & ~2); time.sleep(0.00002); wr(ELBI, 0x3A4, v | 2); ms(1)
    wr(ELBI, 0x1404, 1); ms(2)
    wr(ELBI, 0x1408, 1); ms(1)
    wr(DBI, 0x890, 0x12000)                               # GEN3 EQ off (own conf 0x890)
    gpio(1, 1); ms(20)                                    # PERST deassert
    wr(ELBI, 0x3BC, rd(ELBI, 0x3BC) | 0x1 | (1 << 4))     # APP_REQ_EXIT_L1 + L1_REQ_NAK
    wr(ELBI, 0x3A0, 1 << 1)                               # LINKDOWN_RST manual
    wr(ELBI, 0x3A8, rd(ELBI, 0x3A8) & ~0xfff)             # QCH_SEL: no clock gating
    wr(ELBI, 0x474, 1)                                    # MSTR_PEND_SEL_NAK
    ms(50)
    wr(ELBI, 0x54, 1)                                     # LTSSM enable
    seen, t0 = [], time.monotonic()
    while time.monotonic() - t0 < 2.0:
        s = rd(ELBI, 0x2C8) & 0x3f
        if not seen or seen[-1][1] != s:
            seen.append((time.monotonic() - t0, s))
        if s == 0x11:
            break
    for t, s in seen:
        print(f"t={t * 1000:7.2f} ms  LTSSM {s:#04x} {LTSSM.get(s, '?')}")
    lnk = rd(DBI, 0x80)
    print("DBI 0x80 link ctrl/stat=%#010x  speed=Gen%d width=x%d" % (lnk, (lnk >> 16) & 0xf, (lnk >> 20) & 0x3f))
    print("DBI vendor/device do RC=%#010x" % rd(DBI, 0x0))
    print("RESULTADO:", "LINK L0" if seen and seen[-1][1] == 0x11 else "sem link")
finally:
    power_down()
    print("PCIe ch1 desligado: pmu=%#x" % rd(PMU, PMU_PCIE1_PHY))
