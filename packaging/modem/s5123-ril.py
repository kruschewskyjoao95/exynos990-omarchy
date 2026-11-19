#!/usr/bin/env python3
"""r8s S5123: native control daemon after the cbd boot. Answers INIT_START/PHONE_START like cpif, then
speaks Samsung IPC on the SBD rings: FMT (ch 235) for power/SIM/network, RFS (ch 245) for NV requests
answered from a RAM copy of nv_data.bin (never the real EFS). Started BEFORE cbd (see s5123-ril-run.sh).

Message logic follows Scion hakios.shannon.c (MIT-0; Galaxy S9 Shannon, same IPC family): low power mode
before INIT_END, then version, normal mode, SIM status, registration, serving network, signal. Identities
(IMSI, IMEI, numbers, addresses) are never logged: only headers and state words.

Env: R8S_NV=path of nv_data.bin to copy (default the cbd EFS copy), R8S_RUN_S=seconds online (60).
"""
import importlib.util, mmap, os, struct, subprocess, sys, time

import gpiod
from gpiod.line import Bias, Direction, Value

_s = importlib.util.spec_from_file_location("hs", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                               "ipc-handshake.py"))
hs = importlib.util.module_from_spec(_s)
_s.loader.exec_module(hs)

CH_FMT, CH_RFS = 235, 245
DB_LINK_ACK = 0x10000 | 14      # int_ap2cp_pcie_link_ack + DOORBELL_INT_ADD (modem_ctrl_s5100.c:1404)
MSG_VALID, MSG_CMD, MSG_DATA = 0x80, 0x40, 0x01
LINK = {ch: i for i, (ch, *_) in enumerate(hs.CHANNELS)}       # SBD link id by channel
N = len(hs.CHANNELS)
T0 = time.monotonic()


def log(*a):
    print("[%7.3f]" % (time.monotonic() - T0), *a, flush=True)


class Link:
    def __init__(self):
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.ipc = mmap.mmap(fd, 0x800000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=hs.IPC)
        self.pp = mmap.mmap(fd, 0x100000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=hs.PKTPROC)
        self.db = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=hs.DOORBELL)
        os.close(fd)
        self.mseq, self.wake = 0, None

    def r32(self, o): return struct.unpack_from("<I", self.ipc, o)[0]
    def w32(self, o, v): struct.pack_into("<I", self.ipc, o, v)
    def r16(self, k): return struct.unpack_from("<H", self.ipc, hs.RPWP + 2 * k)[0]
    def w16(self, k, v): struct.pack_into("<H", self.ipc, hs.RPWP + 2 * k, v)

    def put(self, off, data):
        """Word-aligned copy into /dev/mem: memcpy's unaligned tail stores fault (SIGBUS) on Device memory."""
        data = bytes(data) + b"\0" * (-len(data) % 4)
        for k in range(0, len(data), 4):
            self.ipc[off + k:off + k + 4] = data[k:k + 4]

    def get(self, off, n):
        out = b"".join(self.ipc[off + k:off + k + 4] for k in range(0, n + (-n % 4), 4))
        return out[:n]

    def tell(self, msg):
        """pcie_send_ap2cp_irq(): wake the CP if it sleeps, message word, then the doorbell (DOORBELL_INT_ADD)."""
        if self.wake:
            self.wake.ensure_awake()
        self.w32(hs.AP2CP, msg)
        struct.pack_into("<I", self.db, 0, hs.DB_MSG)

    def ul_pending(self):
        return any(self.r16(i) != self.r16(N + i) for i in range(N))

    def send(self, ch, frame, tell=True):
        i = LINK[ch]
        pos, lens, length = hs.RINGS[i, 0]
        rp, wp = self.r16(i), self.r16(N + i)
        if (wp + 1) % length == rp or len(frame) > hs.CHANNELS[i][2]:
            log("UL ch%d full or frame too long (%d B): dropped" % (ch, len(frame)))
            return False
        off = self.r32(pos + 4 * wp)
        self.put(off, frame)
        self.w32(lens + 4 * wp, len(frame))
        self.w16(N + i, (wp + 1) % length)
        if tell:
            self.tell(MSG_VALID | MSG_DATA)
        return True

    def receive(self):
        """Every new DL buffer as (ch, bytes); rp advanced after copying."""
        out = []
        for i in range(N):
            rp, wp = self.r16(2 * N + i), self.r16(3 * N + i)
            pos, lens, length = hs.RINGS[i, 1]
            while rp != wp:
                off, ln = self.r32(pos + 4 * rp), self.r32(lens + 4 * rp) & 0xFFFF
                out.append((hs.CHANNELS[i][0], self.get(off, ln)))
                rp = (rp + 1) % length
                self.w16(2 * N + i, rp)
        return out

    def fmt(self, group, index, typ, data=b"", quiet=False):
        """Samsung IPC request on FMT: SIPC5 header, then len16 mseq aseq group index type."""
        self.mseq = (self.mseq + 1) & 0xFF
        body = struct.pack("<HBBBBB", 7 + len(data), self.mseq, 0, group, index, typ) + data
        if not quiet:
            log("-> FMT %02x %02x type %d seq %d, %d B data" % (group, index, typ, self.mseq, len(data)))
        return self.send(CH_FMT, struct.pack("<BBH", 0xF8, CH_FMT, 4 + len(body)) + body)

    def rfs(self, cmd, rid, body):
        """RFS answer: SIPC5 header, then len32 (6 + body) cmd id."""
        msg = struct.pack("<IBB", 6 + len(body), cmd, rid) + body
        return self.send(CH_RFS, struct.pack("<BBH", 0xF8, CH_RFS, 4 + len(msg)) + msg)


class Wakeup:
    """cp2ap_wakeup (gpm30-0) in, ap2cp_wakeup (gpg1-3) out. On the CP's rising edge: ap2cp_wakeup 1 and the
    pcie_link_ack doorbell, as s5100_poweron_pcie(); the link itself stays up here (no L2 on the falling edge)."""

    def __init__(self, link):
        self.link, self.last, self.down, self.fell = link, None, False, None
        # R8S_PCIE_PM=1: link off when the CP lets go of cp2ap_wakeup (Samsung); the CP does not resume IPC
        # after our power-on yet (research/modem-cbd-boot.md), so off by default: link always up.
        self.pm = os.environ.get("R8S_PCIE_PM") == "1"
        self.cp = gpiod.request_lines("/dev/gpiochip51", consumer="s5123-ril", config={
            0: gpiod.LineSettings(direction=Direction.INPUT, bias=Bias.PULL_DOWN)})
        self.held, self.ap = [], None
        # ap2cp_wakeup gpg1-3, and pda_active gpm25-0: cpif's "ap_status", 1 while the screen is on
        # (s5100_lcd_notifier); at 0 the CP keeps its notifications until the AP sends something.
        for chip, line, name in (("/dev/gpiochip12", 3, "ap2cp_wakeup"), ("/dev/gpiochip46", 0, "pda_active")):
            try:
                req = gpiod.request_lines(chip, consumer="s5123-ril", config={
                    line: gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.ACTIVE)})
                self.held.append(req)
                if name == "ap2cp_wakeup":
                    self.ap = req
                log("%s held at 1" % name)
            except OSError as e:
                log("%s not held (%s)" % (name, e))

    RELINK = "/sys/bus/platform/devices/13d20000.pcie/relink"
    DEVS = ("0001:00:00.0", "0001:01:00.0")
    saved = None

    def pcie_off(self):
        """s5100_poweroff_pcie(): ap2cp_wakeup 0, then the link down (PERST). No doorbell until pcie_on()."""
        self.saved = {d: open("/sys/bus/pci/devices/%s/config" % d, "rb").read() for d in self.DEVS}
        # s51xx_pcie_save_state(): bus master off, MSI off, D3hot
        subprocess.run(["setpci", "-s", "0001:01:00.0", "COMMAND=0000:0004", "CAP_MSI+2.W=0000:0001",
                        "CAP_PM+4.W=0003:0003"], check=True)
        self.ap.set_value(3, Value.INACTIVE)            # s5100_poweroff_pcie(): before the host power-off
        # exynos_pcie_rc_send_pme_turn_off() (pcie-exynos-rc.h offsets): leave L1, PME_Turn_Off, wait for
        # PME_TO_Ack (IRQ0 bit 29), then Enter_L23_READY (LTSSM 0x15)
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        e = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x13D20000)
        os.close(fd)
        r = lambda o: struct.unpack_from("<I", e, o)[0]
        wr = lambda o, v: struct.pack_into("<I", e, o, v)
        wr(0x06C, 1)
        wr(0x3BC, (r(0x3BC) & ~1) | 0x10)
        wr(0x118, 1)
        end = time.monotonic() + 0.02
        while not r(0x000) & (1 << 29) and time.monotonic() < end:
            pass
        ack = bool(r(0x000) & (1 << 29))
        wr(0x118, 0)
        end = time.monotonic() + 0.02
        while (r(0x2C8) & 0x1F) != 0x15 and time.monotonic() < end:
            pass
        log("PME_Turn_Off: ack %d, LTSSM %#x" % (ack, r(0x2C8) & 0x3F))
        open(self.RELINK, "w").write("0")
        self.down = True

    def pcie_on(self):
        """s5100_poweron_pcie(): ap2cp_wakeup 1, link up, the restore cuse-umts start_normal_boot() does, link ack."""
        self.ap.set_value(3, Value.ACTIVE)
        t = time.monotonic()
        open(self.RELINK, "w").write("1")
        subprocess.run(["setpci", "-s", "0001:00:00.0", "COMMAND=0x0006:0x0006"], check=True)
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        dbi = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x13800000)
        sysreg = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x13C20000)
        os.close(fd)
        struct.pack_into("<I", dbi, 0x8E8, 0x10101010)                                   # IOCC
        struct.pack_into("<I", sysreg, 0x704, struct.unpack_from("<I", sysreg, 0x704)[0] | 3)
        struct.pack_into("<2I", dbi, 0x820, 0xF6200000, 0)                               # RC MSI target
        subprocess.run(["setpci", "-s", "0001:01:00.0", "BASE_ADDRESS_0=0x14d60000", "BASE_ADDRESS_1=0",
                        "CAP_MSI+4.L=f6200000", "CAP_MSI+8.W=0000", "CAP_MSI+2.W=0021:0071"], check=True)
        self.down = False
        for d in self.DEVS:
            now = open("/sys/bus/pci/devices/%s/config" % d, "rb").read()
            old = self.saved.get(d, b"") if self.saved else b""
            diff = [o for o in range(0, min(len(now), len(old)), 4) if now[o:o + 4] != old[o:o + 4]]
            log("%s config dwords changed by the cycle: %s" % (d, " ".join("%#x:%s->%s" % (o, old[o:o + 4][::-1].hex(),
                now[o:o + 4][::-1].hex()) for o in diff[:24])))
        sta = lambda: subprocess.run(["setpci", "-s", "0001:01:00.0", "STATUS"], capture_output=True,
                                     text=True).stdout.strip()
        subprocess.run(["setpci", "-s", "0001:01:00.0", "STATUS=0800"], check=True)   # clear >TAbort (RW1C)
        # The CP re-arms its endpoint after PERST on its own time: ack again until it has (no abort seen).
        for delay in (0, 0.05, 0.2):
            time.sleep(delay)
            struct.pack_into("<I", self.link.db, 0, DB_LINK_ACK)
            log("pcie_link_ack at +%.0f ms after link up: EP status %s" % ((time.monotonic() - t) * 1e3, sta()))

    def ensure_awake(self):
        """s5100_try_gpio_cp_wakeup() + s5100_poweron_pcie(): ap2cp_wakeup 1, wait for cp2ap_wakeup, link ack."""
        if self.ap is None or self.ap.get_value(3) == Value.ACTIVE:
            return
        if self.down:
            self.pcie_on()
            return
        self.ap.set_value(3, Value.ACTIVE)
        end = time.monotonic() + 0.3
        while self.cp.get_value(0) != Value.ACTIVE and time.monotonic() < end:
            time.sleep(0.001)
        up = self.cp.get_value(0) == Value.ACTIVE
        if up:
            struct.pack_into("<I", self.link.db, 0, DB_LINK_ACK)
        self.last = up
        log("AP woke the CP: cp2ap_wakeup %d%s" % (up, ", pcie_link_ack sent" if up else " (no answer in 300 ms)"))

    def poll(self):
        v = self.cp.get_value(0) == Value.ACTIVE
        if v != self.last:
            log("cp2ap_wakeup %d" % v)
            if v and self.down:
                self.pcie_on()                          # the CP asks for the link: it has something to send
            self.fell = None if v else time.monotonic()
            self.last = v
        # 30 ms after the fall, still low and nothing of ours waiting: let the CP sleep (s5100_poweroff_pcie)
        if (self.pm and self.fell and time.monotonic() - self.fell > 0.03 and not self.down and self.ap
                and not self.link.ul_pending()):
            self.fell = None
            self.pcie_off()
            log("PCIe off (CP may sleep)")


class State:
    sim = reg = tech = phone = None
    oper = ""
    dbm = bars = None


def on_fmt(st, m):
    if len(m) < 7:
        return log("<- FMT short (%d B)" % len(m))
    g, ix, ty, d = m[4], m[5], m[6], m[7:]
    kind = {1: "ind", 2: "resp", 3: "noti"}.get(ty, "?")
    if g == 0x80 and len(d) >= 5:
        log("<- general response to %02x %02x type %d: result %#x" % (d[0], d[1], d[2], d[3] | d[4] << 8))
    elif g == 0x01 and ix == 0x07 and d:
        st.phone = d[0]
        log("<- PHONE STATE %d (%s)" % (d[0], {1: "low power", 2: "NORMAL"}.get(d[0], "?")))
    elif g == 0x01:
        log("<- PWR %02x %s: %s" % (ix, kind, d[:8].hex()))
    elif g == 0x05 and ix in (0x01, 0x07) and len(d) <= 2:
        if ix == 1 and d:
            st.sim = d[0]
        log("<- SIM %s: %s (%s)" % ("status" if ix == 1 else "card type", d.hex(),
            {0x00: "initialising", 0x80: "NO CARD", 0x82: "READY", 0x83: "phonebook ready"}.get(d[0] if d else -1,
                                                                                               "lock/other")))
    elif g == 0x08 and ix == 0x05 and len(d) >= 3:
        st.tech, st.reg = d[0], d[2]
        log("<- REGISTRATION tech %d domain %d state %d (%s)" % (d[0], d[1], d[2], {1: "none", 2: "HOME",
            3: "SEARCHING", 4: "EMERGENCY ONLY", 5: "unknown", 6: "ROAMING"}.get(d[2], "?")))
    elif g == 0x08 and ix == 0x03:
        s = bytes(d)
        code = next((s[i:i + k].decode() for i in range(len(s)) for k in (6, 5)
                     if s[i:i + k].isdigit()), "")
        st.oper = code or st.oper
        log("<- SERVING NETWORK operator %s" % (code or "?"))
    elif g == 0x07 and ix in (0x01, 0x06) and len(d) >= 2:
        if ix == 1 and d[0] & 1:
            st.bars = d[1]
        elif ix == 6:
            st.dbm = -d[0]
        log("<- SIGNAL %s bars=%s dbm=%s" % ("icon" if ix == 1 else "strength", st.bars, st.dbm))
    elif g == 0x0A and ix == 0x01 and ty == 2 and len(d) >= 33:
        txt = lambda b: b.split(b"\0")[0].decode("ascii", "replace")
        log("<- VERSION sw=%s hw=%s" % (txt(d[1:33]), txt(d[33:65]) if len(d) >= 65 else "?"))
    else:
        log("<- FMT %02x %02x %s, %d B" % (g, ix, kind, len(d)))   # body not logged: may carry identities


class Rfs:
    """NV requests answered from a RAM copy (Scion rfs_received/rfs_nv_answer); writes stay in RAM."""

    def __init__(self, link, nv):
        self.link, self.nv, self.more, self.w = link, nv, 0, None

    def answer_nv(self, cmd, rid, ok, off, ln):
        body = struct.pack("<BII", 1 if ok else 0, off, ln)
        if cmd == 1 and ok:
            body += bytes(self.nv[off:off + ln])
        self.link.rfs(cmd, rid, body)

    def write_data(self, d):
        off, ln, got, rid = self.w
        take = d[:ln - got]
        self.nv[off + got:off + got + len(take)] = take
        got += len(take)
        self.w = (off, ln, got, rid)
        if got == ln:
            self.w = None
            self.answer_nv(2, rid, True, off, ln)
            log("RFS NV write %#x+%d kept in RAM" % (off, ln))

    def on(self, m):
        if self.more:
            k = min(len(m), self.more)
            if self.w:
                self.write_data(m[:k])
            self.more -= k
            return
        if len(m) < 6:
            return log("<- RFS short (%d B)" % len(m))
        ln, cmd, rid = struct.unpack_from("<IBB", m)
        self.more = max(0, ln - len(m))
        if cmd in (1, 2) and len(m) >= 14:
            off, n = struct.unpack_from("<II", m, 6)
            fits = off <= len(self.nv) and n <= len(self.nv) - off
            if cmd == 1:
                ok = fits and n <= 2048 - 4 - 6 - 9
                self.answer_nv(1, rid, ok, off, n if ok else 0)
                return log("<- RFS NV read %#x+%d: %s" % (off, n, "answered" if ok else "refused"))
            if not fits or n > ln - 14:
                self.answer_nv(2, rid, False, off, n)
                return log("<- RFS NV write %#x+%d: refused" % (off, n))
            self.w = (off, n, 0, rid)
            return self.write_data(m[14:14 + n])
        if cmd == 0x11:
            self.link.rfs(0x11, rid, struct.pack("<ii", -1, 2))      # open file: ENOENT, as Scion
            return log("<- RFS open file (id %d): answered ENOENT" % rid)
        log("<- RFS command %#x id %d, %d B: not answered" % (cmd, rid, ln))


def main():
    nv_path = os.environ.get("R8S_NV", "/run/android-root/mnt/vendor/efs/nv_data.bin")
    run_s = float(os.environ.get("R8S_RUN_S", "60"))
    nv = bytearray(open(nv_path, "rb").read())
    assert len(nv) == 1 << 20, "nv_data.bin should be 1 MiB"
    L, st = Link(), State()
    rfs = Rfs(L, nv)
    sbd, pp_t = hs.sbd_table(), hs.pktproc_table()

    end = time.monotonic() + 120
    while L.r32(hs.CP2AP) == hs.INIT_START and time.monotonic() < end:
        time.sleep(0.001)
    while L.r32(hs.CP2AP) != hs.INIT_START and time.monotonic() < end:
        time.sleep(0.0005)
    if L.r32(hs.CP2AP) != hs.INIT_START:
        sys.exit(log("no INIT_START"))
    L.ipc[0x800:0x10000] = sbd
    L.pp[:len(pp_t)] = pp_t
    L.tell(hs.PIF_INIT_DONE)
    log("INIT_START -> PIF_INIT_DONE")
    end = time.monotonic() + 10
    while L.r32(hs.CP2AP) != hs.PHONE_START and time.monotonic() < end:
        time.sleep(0.001)
    if L.r32(hs.CP2AP) != hs.PHONE_START:
        sys.exit(log("no PHONE_START"))
    L.w32(0, 0); L.w32(4, 0)                                  # init_legacy_link()
    for o in range(0x8, 0x28, 4):
        L.w32(o, 0)
    L.w32(0, 0xAA); L.w32(4, 1)
    L.fmt(0x01, 0x07, 0x01, b"\x01\x00")                      # low power first, waits in the ring (Scion)
    L.tell(hs.INIT_END)
    log("PHONE_START -> low power queued, INIT_END")

    wake = Wakeup(L)
    L.wake = wake
    t_up, asked_normal, asked_ver, last_msg, last_snap = time.monotonic(), False, False, None, None
    kick = float(os.environ.get("R8S_KICK_S", "0"))   # >0: an empty MSG_DATA doorbell this often (see research)
    poll = float(os.environ.get("R8S_POLL_S", "2"))   # registration GET this often: a UL frame lets the CP flush
    next_poll = 5.0
    next_kick, shown_link, online = 0.0, False, False   # online: the CP has taken INIT_END (sent us a frame)
    while time.monotonic() - t_up < run_s:
        wake.poll()
        msg = L.r32(hs.CP2AP)
        snap = (msg, L.r32(hs.AP2CP), L.r16(LINK[CH_FMT]), L.r16(N + LINK[CH_FMT]), L.r32(0), L.r32(4))
        if snap != last_snap:
            log("cp2ap=%#x ap2cp=%#x FMT UL rp/wp=%d/%d magic=%#x access=%d" % snap)
            last_snap = snap
        if msg != last_msg:
            last_msg = msg
            if msg == hs.PHONE_START:
                L.tell(hs.INIT_END)                           # not taken yet: told again, as cpif
            elif msg & MSG_CMD and (msg & 0x3F) in (0x07, 0x09):
                sys.exit(log("CP CRASH (%#x)" % msg))
        for ch, m in L.receive():
            online = True
            if ch == CH_FMT:
                on_fmt(st, m[4:] if m[:1] == b"\xf8" else m)
            elif ch == CH_RFS:
                rfs.on(m[4:] if m[:1] == b"\xf8" and not rfs.more else m)
            else:
                log("<- ch%d %d B" % (ch, len(m)))
        now = time.monotonic() - t_up
        if not asked_ver and now > 2:
            asked_ver = True
            L.fmt(0x0A, 0x01, 0x02, b"\xff")
        if kick and online and now >= next_kick:
            next_kick = now + kick
            L.tell(MSG_VALID | MSG_DATA)
        if not shown_link and now > 20:
            shown_link = True
            for dev in ("0001:00:00.0", "0001:01:00.0"):
                out = subprocess.run(["lspci", "-vv", "-s", dev], capture_output=True, text=True).stdout
                log(dev, " | ".join(l.strip() for l in out.splitlines() if any(k in l for k in ("Control:", "Status:", "DevSta", "UESta", "CESta", "LnkSta:"))))
        if poll and online and now >= next_poll:
            next_poll = now + poll
            L.fmt(0x08, 0x05, 0x02, quiet=True)
        if not asked_normal and now > 3:
            asked_normal = True
            L.fmt(0x01, 0x07, 0x01, b"\x02\x02")              # normal mode: the radio may register
        time.sleep(0.002)
    L.fmt(0x01, 0x07, 0x01, b"\x01\x00")                      # back to low power before power-off
    time.sleep(1)
    for ch, m in L.receive():
        if ch == CH_FMT:
            on_fmt(st, m[4:] if m[:1] == b"\xf8" else m)
    log("summary: sim=%s phone=%s reg=%s tech=%s operator=%s bars=%s dbm=%s" %
        (st.sim, st.phone, st.reg, st.tech, st.oper or "?", st.bars, st.dbm))


if __name__ == "__main__":
    main()
