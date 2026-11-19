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


class Data:
    """rmnet0 (TUN) <-> the CP. UL: raw IP on the SBD ring of ch 10 (QOS_HIPRIO), buff_len = len | ch << 16, no
    link header (sbd_pio_tx). DL: PKTPROC sktbuf descriptors (pktproc_get_pkt_from_sktbuf_mode); descriptor k
    always owns cell k, refilled at fore as pktproc_fill_data_addr() does."""
    CH = 10
    CP_BASE, CELL, PAD = 0x28000000, 2048 + 512, 66

    def __init__(self, link, st):
        import fcntl
        self.L, self.st = link, st
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self.pp = mmap.mmap(fd, hs.PP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=hs.PKTPROC)
        os.close(fd)
        self.num = struct.unpack_from("<I", self.pp, 8)[0]
        self.done = 0
        self.tun = os.open("/dev/net/tun", os.O_RDWR | os.O_NONBLOCK)
        fcntl.ioctl(self.tun, 0x400454CA, struct.pack("16sH", b"rmnet0", 0x0001 | 0x1000))  # TUNSETIFF TUN|NO_PI
        self.up = self.down = 0

    def configure(self):
        ip = "%d.%d.%d.%d" % tuple(self.st.ip4)
        for cmd in (["ip", "addr", "flush", "dev", "rmnet0"], ["ip", "addr", "add", ip + "/32", "dev", "rmnet0"],
                    ["ip", "link", "set", "rmnet0", "mtu", "1400", "up"],
                    ["ip", "route", "replace", "default", "dev", "rmnet0", "metric", "900"]):
            subprocess.run(cmd, check=True)
        log("rmnet0 up (address from the CP), default route metric 900 (Wi-Fi keeps priority)")

    def pump(self):
        while True:                                      # UL: tun -> SBD
            try:
                pkt = os.read(self.tun, 2048)
            except BlockingIOError:
                break
            if self.up < 12:
                log("UL " + self.describe(pkt))
            if self.send(pkt):
                self.up += 1
        r = lambda o: struct.unpack_from("<I", self.pp, o)[0]
        rear = r(20)
        got = False
        while self.done != rear:                         # DL: PKTPROC -> tun
            d = 0x100 + 16 * self.done
            addr, ctl = struct.unpack_from("<IBB", self.pp, d)[0], 0
            length, chan = struct.unpack_from("<H", self.pp, d + 8)[0], self.pp[d + 14]
            off = addr - self.CP_BASE
            if 0 < length <= 2048 and 0x100000 <= off and off + length <= hs.PP_SIZE and chan == self.CH:
                start = off & ~3
                end = (off + length + 3) & ~3
                data = b"".join(self.pp[p:p + 4] for p in range(start, end, 4))
                pkt = data[off - start:off - start + length]
                try:
                    os.write(self.tun, pkt)
                    self.down += 1
                except OSError:
                    pass
            else:
                log("PKTPROC bad descriptor %d: len %d ch %d off %#x" % (self.done, length, chan, off))
            fore = r(16)                                 # refill: descriptor fore gets its own cell back
            struct.pack_into("<I", self.pp, 0x100 + 16 * fore, self.CP_BASE + 0x100000 + fore * self.CELL + self.PAD)
            ctl = (0x80 if fore == 0 else 0) | (0x08 if fore == self.num - 1 else 0)
            struct.pack_into("<I", self.pp, 0x100 + 16 * fore + 4, ctl << 8)   # data_addr_msb 0, control, status 0
            struct.pack_into("<I", self.pp, 16, (fore + 1) % self.num)
            self.done = (self.done + 1) % self.num
            got = True
        return got

    @staticmethod
    def describe(pkt):
        if pkt[:1] and pkt[0] >> 4 == 4 and len(pkt) >= 20:
            return "v4 proto %d len %d %d.x->%d.x" % (pkt[9], len(pkt), pkt[12], pkt[16])
        if pkt[:1] and pkt[0] >> 4 == 6 and len(pkt) >= 40:
            return "v6 next %d len %d" % (pkt[6], len(pkt))
        return "? %d B %s" % (len(pkt), pkt[:8].hex())

    def deliver(self, pkt):
        if self.down < 12:
            log("DL " + self.describe(pkt))
        try:
            os.write(self.tun, pkt)
            self.down += 1
        except OSError as e:
            log("rmnet0 write: %s" % e)

    def send(self, pkt):
        L, i = self.L, LINK[11]                         # QOS_NORMAL ring (sbd_ch2rb); the tag says rmnet0
        pos, lens, length = hs.RINGS[i, 0]
        rp, wp = L.r16(i), L.r16(N + i)
        if (wp + 1) % length == rp or len(pkt) > 2048:
            return False
        L.put(L.r32(pos + 4 * wp), pkt)
        L.w32(lens + 4 * wp, len(pkt) | self.CH << 16)
        L.w16(N + i, (wp + 1) % length)
        L.tell(MSG_VALID | MSG_DATA)
        return True


class State:
    sim = reg = reg_cs = reg_ps = tech = phone = pdp_state = ip4 = dns4 = None
    last_result = None
    oper = ""
    dbm = bars = None


def on_fmt(st, m):
    if len(m) < 7:
        return log("<- FMT short (%d B)" % len(m))
    g, ix, ty, d = m[4], m[5], m[6], m[7:]
    kind = {1: "ind", 2: "resp", 3: "noti"}.get(ty, "?")
    if g == 0x80 and len(d) >= 5:
        st.last_result = (d[0], d[1], d[3] | d[4] << 8)
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
    elif g == 0x08 and ix == 0x05 and ty == 2:
        pass                                            # our poll's answer: another layout, not the state
    elif g == 0x08 and ix == 0x05 and len(d) >= 3:
        if d[1] == 2:
            st.reg_cs = d[2]
        elif d[1] == 3:
            st.reg_ps = d[2]
        if d[1] in (2, 3) or st.reg is None:            # PS/CS domains; domain 0 is not a registration
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
    elif g == 0x0D and ix == 0x10 and len(d) >= 2:
        log("<- DATA CALL STATUS context %d status %d (%s) cause %#x [%s]" % (d[0], d[1], {0: "not enabled",
            1: "ENABLED", 3: "disabled"}.get(d[1], "?"), d[2] if len(d) > 2 else 0, d.hex()))
        st.pdp_state = d[1]
    elif g == 0x0D and ix == 0x09:
        if len(d) >= 3 + 8:
            st.ip4, st.dns4 = bytes(d[3:7]), bytes(d[7:11])
            log("<- DATA ADDRESS context %d flags %#x cause %#x: IPv4 %d.x.x.x, DNS %d.x.x.x" % (
                d[0], d[1], d[2], d[3], d[7]))
        else:
            log("<- DATA ADDRESS %s, %d B" % (kind, len(d)))
    elif g == 0x0D and ix in (0x0C, 0x0F):
        log("<- DATA %02x %s, %d B: %s" % (ix, kind, len(d), d.hex()))
    elif g == 0x0D and ty == 2 and ix not in (0x06, 0x09):
        log("<- DATA %02x response, %d B: %s" % (ix, len(d), d[:48].hex()))   # diagnosis of the data group
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
    apn = os.environ.get("R8S_APN", "").encode()        # empty: no data call
    data, step, step_t = None, 0, 0.0
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
            elif ch in (10, 11) and data:
                data.deliver(m)                         # DL on the multipdp SBD rings: raw IP, no link header
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
        if apn and st.reg_ps in (2, 6) and step == 0 and now > 5:
            # IpcProtocol41Data::IpcTxPsAttach: 10-byte message, data [attach 1, 0, 0]
            st.last_result = None
            L.fmt(0x0D, 0x03, 0x03, b"\x01\x00\x00")
            step, step_t = -2, now
        elif step == -2 and (st.last_result and st.last_result[:2] == (0x0D, 0x03) or now - step_t > 5):
            log("PS attach result %s" % (hex(st.last_result[2]) if st.last_result else "none in 5 s"))
            step = -3
        elif apn and step == -3:
            # IpcProtocol41Data::IpcTxDefinePdpContext: 149-byte message (142 B data): enable, cid, PDP type 2 (IP),
            # APN from offset 3 (libsec-ril.so, read for the layout only)
            d = bytearray(142)
            d[0], d[1], d[2] = 1, 1, 2
            d[3:3 + len(apn)] = apn
            st.last_result = None
            L.fmt(0x0D, 0x01, 0x03, bytes(d))             # define context 1 (Scion data_stage)
            step, step_t = 1, now
        elif step == 1 and st.last_result and st.last_result[:2] == (0x0D, 0x01):
            log("context definition result %#x" % st.last_result[2])
            ok = st.last_result[2] == 0x8000
            st.last_result = None
            if not ok:
                step = -1
            else:
                # IpcProtocol41Data::IpcTxSetPdpContext: 248-byte message (241 B data): state 1 (activate), cid,
                # u32 flags (bit0 user, bit1 password, bit4 auth), user[100] at 6, password[100] at 106, auth at 238
                # (1 PAP, 2 CHAP)
                d = bytearray(241)
                d[0], d[1] = 1, 1
                user, pw = os.environ.get("R8S_APN_USER", "").encode(), os.environ.get("R8S_APN_PASS", "").encode()
                flags = (1 if user else 0) | (2 if pw else 0)
                if user or pw:
                    flags |= 0x10
                    d[238] = 1
                struct.pack_into("<I", d, 2, flags)
                d[6:6 + len(user)], d[106:106 + len(pw)] = user, pw
                L.fmt(0x0D, 0x04, 0x03, bytes(d))             # activate context 1
                step, step_t = 2, now
        elif step == 2 and st.last_result and st.last_result[:2] == (0x0D, 0x04):
            log("activation result %#x" % st.last_result[2])
            st.last_result = None
            step, step_t = 3, now
        elif step == 3 and not st.ip4 and now - step_t > 3 and not getattr(st, "asked_ip", False):
            st.asked_ip = True
            L.fmt(0x0D, 0x04, 0x02)                       # contexts' state
            L.fmt(0x0D, 0x09, 0x02, b"\x01")              # IP configuration of context 1
        elif step == 3 and st.ip4 and data is None:
            data = Data(L, st)
            data.configure()
            step = 4
        if data:
            data.pump()
        if poll and online and now >= next_poll:
            next_poll = now + (0.3 if data else poll)   # with data up: DL also waits for a UL frame
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
    if data:
        i = LINK[11]
        log("data: %d packets up, %d down; UL ring rp/wp %d/%d" % (data.up, data.down, L.r16(i), L.r16(N + i)))
    log("summary: sim=%s phone=%s reg_cs=%s reg_ps=%s tech=%s operator=%s bars=%s dbm=%s" %
        (st.sim, st.phone, st.reg_cs, st.reg_ps, st.tech, st.oper or "?", st.bars, st.dbm))


if __name__ == "__main__":
    main()
