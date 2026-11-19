#!/usr/bin/env python3
"""r8s S5123: native control daemon after the cbd boot. Answers INIT_START/PHONE_START like cpif, then
speaks Samsung IPC on the SBD rings: FMT (ch 235) for power/SIM/network, RFS (ch 245) for NV requests
answered from a RAM copy of nv_data.bin (never the real EFS). Started BEFORE cbd (see s5123-ril-run.sh).

Message logic follows Scion hakios.shannon.c (MIT-0; Galaxy S9 Shannon, same IPC family): low power mode
before INIT_END, then version, normal mode, SIM status, registration, serving network, signal. Identities
(IMSI, IMEI, numbers, addresses) are never logged: only headers and state words.

Env: R8S_NV=path of nv_data.bin to copy (default the cbd EFS copy), R8S_RUN_S=seconds online (60).
"""
import importlib.util, mmap, os, struct, sys, time

_s = importlib.util.spec_from_file_location("hs", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                               "ipc-handshake.py"))
hs = importlib.util.module_from_spec(_s)
_s.loader.exec_module(hs)

CH_FMT, CH_RFS = 235, 245
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
        self.mseq = 0

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
        """pcie_send_ap2cp_irq(): message word, then the doorbell with DOORBELL_INT_ADD."""
        self.w32(hs.AP2CP, msg)
        struct.pack_into("<I", self.db, 0, hs.DB_MSG)

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

    def fmt(self, group, index, typ, data=b""):
        """Samsung IPC request on FMT: SIPC5 header, then len16 mseq aseq group index type."""
        self.mseq = (self.mseq + 1) & 0xFF
        body = struct.pack("<HBBBBB", 7 + len(data), self.mseq, 0, group, index, typ) + data
        log("-> FMT %02x %02x type %d seq %d, %d B data" % (group, index, typ, self.mseq, len(data)))
        return self.send(CH_FMT, struct.pack("<BBH", 0xF8, CH_FMT, 4 + len(body)) + body)

    def rfs(self, cmd, rid, body):
        """RFS answer: SIPC5 header, then len32 (6 + body) cmd id."""
        msg = struct.pack("<IBB", 6 + len(body), cmd, rid) + body
        return self.send(CH_RFS, struct.pack("<BBH", 0xF8, CH_RFS, 4 + len(msg)) + msg)


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

    t_up, asked_normal, asked_ver, last_msg = time.monotonic(), False, False, None
    while time.monotonic() - t_up < run_s:
        msg = L.r32(hs.CP2AP)
        if msg != last_msg:
            last_msg = msg
            if msg == hs.PHONE_START:
                L.tell(hs.INIT_END)                           # not taken yet: told again, as cpif
            elif msg & MSG_CMD and (msg & 0x3F) in (0x07, 0x09):
                sys.exit(log("CP CRASH (%#x)" % msg))
        for ch, m in L.receive():
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
