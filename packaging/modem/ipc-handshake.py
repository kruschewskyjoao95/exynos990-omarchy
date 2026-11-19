#!/usr/bin/env python3
"""r8s S5123: answer CP INIT_START (0xc1) the way cpif cmd_init_start_handler() does, within ~1 ms,
then record what the CP changes in shared memory. Started BEFORE cbd; waits for a fresh 0xc1.
Tables: LineageOS 97369af7 cpif (create_sbd_mem_map/init_sbd_link, pktproc_create/pktproc_init),
geometry from exynos9830-universal9830-cp-s5123-sipc.dtsi. Root, kernel with 0140-0143.
"""
import mmap, os, struct, subprocess, sys, time

IPC, PKTPROC, DOORBELL = 0xF0000000, 0xD0000000, 0x14060000
AP2CP, CP2AP, AP2CP_ST, CP2AP_ST = 0x400, 0x404, 0x408, 0x40C
INIT_START, INIT_END, PIF_INIT_DONE, PHONE_START = 0xC1, 0xC2, 0xCD, 0xC8
DB_MSG = 0x10000 | 0   # int_ap2cp_msg 0 + DOORBELL_INT_ADD (cpif include/legacy.h)
PP_SIZE = 32 << 20  # our reserved pktproc region (LineageOS reserves 64 MiB)

# (ch, ul_len, ul_size, dl_len, dl_size): SBD iodevs in DT order; PS ch 10-24 skipped, MULTI_RAW -> 10, 11.
CHANNELS = ((35, 16, 2048, 16, 2048), (235, 16, 4096, 32, 4096), (236, 16, 4096, 32, 4096),
            (245, 16, 2048, 512, 2048), (1, 32, 2048, 64, 2048), (25, 16, 2048, 16, 2048),
            (28, 16, 2048, 128, 2048), (244, 16, 2048, 32, 2048), (10, 1024, 2048, 256, 2048),
            (11, 512, 2048, 1024, 2048))


RINGS = {}  # (link id, dir) -> (IPC offset of buff_pos_array, of buff_len_array, length); filled by sbd_table()
RPWP = 0x800 + 12 + 32 * 2 * 8 + 32 * 2 * 20   # u16 rp[UL][n], wp[UL][n], rp[DL][n], wp[DL][n]


def sbd_table():
    """Bytes for IPC[0x800:0x10000]: g_desc, rp/wp arrays, buff_pos/len arrays; buffers from 0x10000."""
    t = bytearray(0xF800)
    base, n = 0x800, len(CHANNELS)
    rb_desc = 12 + 32 * 2 * 8                  # after version/num/rpwp + rb_ch[32][2]
    rpwp = rb_desc + 32 * 2 * 20               # after rb_desc[32][2]
    cells, data = rpwp + 2 * 2 * 2 * n, 0x10000
    struct.pack_into("<3I", t, 0, 1, n, base + rpwp)
    for i, (ch, *geo) in enumerate(CHANNELS):
        for d in (0, 1):
            length, size = geo[2 * d], geo[2 * d + 1]
            desc = rb_desc + (2 * i + d) * 20
            struct.pack_into("<2I", t, 12 + (2 * i + d) * 8, base + desc, base + cells)
            struct.pack_into("<4HI4H", t, desc, ch, 0, d, 1, 0x81, length, i, size, 0)
            for s in range(length):
                struct.pack_into("<I", t, cells + 4 * s, data + s * size)
            RINGS[i, d] = (base + cells, base + cells + 4 * length, length)
            cells += 8 * length
            data += length * size
    assert cells <= len(t) and data <= 0x800000
    return t


def pktproc_table():
    """Bytes for PKTPROC[0:]: info_v2 (1 queue, sktbuf mode, 2048) + filled sktbuf descriptors."""
    cp_base, cell = 0x28000000, 2048 + 512
    data = PP_SIZE - 0x100000
    num = (data // cell) * 25 // 100
    t = bytearray(0x100 + num * 16)
    struct.pack_into("<6I", t, 0, 1 | 1 << 4 | 2048 << 8, cp_base + 0x100, num, cp_base + 0x100000,
                     num - 1, 0)
    for s in range(num - 1):                   # pktproc_fill_data_addr(): HEAD on 0, +NET_SKB_PAD+NET_IP_ALIGN
        struct.pack_into("<IBB", t, 0x100 + 16 * s, cp_base + 0x100000 + s * cell + 66, 0, 0x80 if s == 0 else 0)
    return t


def gpio(chip, line):
    r = subprocess.run(["gpioget", "-b", "pull-down", "-c", chip, str(line)], capture_output=True, text=True)
    return r.stdout.strip().split("=")[-1]


if __name__ == "__main__":
    sbd, pp_t = sbd_table(), pktproc_table()
    assert struct.unpack_from("<3I", sbd) == (1, 10, 0x800 + 12 + 512 + 1280)
    if os.getenv("R8S_IPC_APPLY") != "1":
        print("self-check ok: SBD", len(sbd), "B, PKTPROC", len(pp_t), "B")
        sys.exit()
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    ipc = mmap.mmap(fd, 0x800000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=IPC)
    pp = mmap.mmap(fd, 0x100000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=PKTPROC)
    db = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=DOORBELL)
    elbi = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x13D20000)
    w = lambda m, o: struct.unpack_from("<I", m, o)[0]
    log = lambda *a: print("[%8.3f]" % time.monotonic(), *a, flush=True)

    end = time.monotonic() + 120
    while w(ipc, CP2AP) == INIT_START and time.monotonic() < end:   # stale value from an earlier run
        time.sleep(0.001)
    while w(ipc, CP2AP) != INIT_START and time.monotonic() < end:
        time.sleep(0.0005)
    if w(ipc, CP2AP) != INIT_START:
        sys.exit(log("no INIT_START"))
    t0 = time.monotonic()
    ipc[0x800:0x10000] = sbd
    pp[:len(pp_t)] = pp_t
    struct.pack_into("<I", ipc, AP2CP, PIF_INIT_DONE)
    struct.pack_into("<I", db, 0, DB_MSG)
    log("INIT_START -> PIF_INIT_DONE in %.1f ms, doorbell readback %#x" % ((time.monotonic() - t0) * 1e3, w(db, 0)))

    ref_ipc, ref_pp = bytes(ipc[:0x800000]), bytes(pp[:0x100000])
    last = None
    while time.monotonic() - t0 < 10:
        st = (w(ipc, 0), w(ipc, 4), w(ipc, AP2CP), w(ipc, CP2AP), w(ipc, AP2CP_ST), w(ipc, CP2AP_ST),
              w(pp, 16), w(pp, 20), w(elbi, 0x2c8) & 0x3f)
        if st != last:
            log("magic=%#x access=%d ap2cp=%#x cp2ap=%#x ap_st=%#x cp_st=%#x pp fore/rear=%d/%d ltssm=%#x" % st)
            last = st
        if st[3] == PHONE_START:
            log("PHONE_START received")
            break

        time.sleep(0.001)
    if st[3] != PHONE_START:
        sys.exit(log("no PHONE_START"))

    # cmd_phone_start_handler(): init_legacy_link() then, with FMT/RFS open (rild_ready), INIT_END.
    w32 = lambda o, v: struct.pack_into("<I", ipc, o, v)
    w32(0, 0); w32(4, 0)
    for o in range(0x8, 0x28, 4):
        w32(o, 0)
    w32(0, 0xAA); w32(4, 1)
    w32(AP2CP, INIT_END)
    struct.pack_into("<I", db, 0, DB_MSG)
    log("init_legacy_link magic=%#x access=%d, INIT_END sent" % (w(ipc, 0), w(ipc, 4)))

    n = len(CHANNELS)
    u16 = lambda k: struct.unpack_from("<H", ipc, RPWP + 2 * k)[0]
    last, t1 = None, time.monotonic()
    while time.monotonic() - t1 < 20:
        ptr = tuple(u16(k) for k in range(4 * n))
        msg = (w(ipc, 0), w(ipc, CP2AP), w(ipc, CP2AP_ST))
        if (ptr, msg) != last:
            log("magic=%#x cp2ap=%#x cp_st=%#x rp/wp UL=%s/%s DL=%s/%s" % (msg + (ptr[:n], ptr[n:2 * n],
                ptr[2 * n:3 * n], ptr[3 * n:])))
            last = (ptr, msg)
        for i in range(n):                    # drain DL rings: dump each new buffer, then advance rp
            rp, wp = u16(2 * n + i), u16(3 * n + i)
            pos, lens, length = RINGS[i, 1]
            while rp != wp:
                off, ln = w(ipc, pos + 4 * rp), w(ipc, lens + 4 * rp) & 0xFFFF   # CP puts ch in bits 16-23
                log("  DL ch%d [%d] %d B: %s" % (CHANNELS[i][0], rp, ln, ipc[off:off + min(ln, 64)].hex()))
                rp = (rp + 1) % length
                struct.pack_into("<H", ipc, RPWP + 2 * (2 * n + i), rp)
        time.sleep(0.002)
    log(subprocess.run(["lspci", "-s", "0001:01:00.0", "-vv"], capture_output=True, text=True).stdout[:900])
    log("phone_active=%s cp2ap_wakeup=%s ps_hold=%s" % (gpio("gpiochip49", 0), gpio("gpiochip51", 0),
                                                       gpio("gpiochip52", 0)))
