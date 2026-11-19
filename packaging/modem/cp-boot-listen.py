#!/usr/bin/env python3
# Runs on the phone as root, kernel with 0140-0142. Milestone 4b probe: prepare the CP IPC region
# the way LineageOS link_start_normal_boot()/init_legacy_link() do (magic "BOOT", legacy queues
# zeroed), bring the PCIe link up, ring the pcie_link_ack doorbell and print whatever the CP boot
# loader puts in the legacy RX queues (SIPC5 frames: 0xF8|flags, channel, 16-bit length).
# Layout: exynos9830-universal9830-cp-s5123-sipc.dtsi legacy_* offsets. Polled: no MSI yet.
import functools, mmap, os, struct, subprocess, sys, time
print = functools.partial(print, flush=True)

IPC_BASE, IPC_SIZE = 0xF0000000, 0x800000
DOORBELL = 0x14260000            # s5123-modem: root port window + 0x60000 (dmesg)
MAGIC_BOOT = 0x424F4F54
INT_AP2CP_MSG, INT_PCIE_LINK_ACK = 0x10000 | 0, 0x10000 | 14   # + DOORBELL_INT_ADD (cpif legacy.h)
FMT_HT, FMT_BUF, FMT_TXQ, FMT_RXQ = 0x8, 0x1000, 0x1000, 0x1000
RAW_HT, RAW_BUF, RAW_TXQ, RAW_RXQ = 0x18, 0x3000, 0x1FD000, 0x200000
D = os.path.dirname(os.path.abspath(__file__))

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
ipc = mmap.mmap(fd, IPC_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=IPC_BASE)
r32 = lambda o: struct.unpack_from("<I", ipc, o)[0]
def w32(o, v): struct.pack_into("<I", ipc, o, v)

def queues():
    return {"fmt": [r32(FMT_HT + i * 4) for i in range(4)], "raw": [r32(RAW_HT + i * 4) for i in range(4)]}

def dump_rx(name, ht, buf, txq, rxq):
    head, tail = r32(ht + 8), r32(ht + 12)       # rxq head/tail (CP writes head)
    if head == tail:
        return
    base = buf + txq
    n = (head - tail) % rxq
    data = bytes(ipc[base + ((tail + i) % rxq)] for i in range(min(n, 256)))
    print(f"  RX {name}: head={head} tail={tail} ({n} B): {data[:64].hex()}")
    if data and (data[0] & 0xF8) == 0xF8 and len(data) >= 4:
        print(f"    SIPC5 cfg={data[0]:#04x} ch={data[1]} len={data[2] | data[3] << 8} payload={data[4:20].hex()}")

subprocess.run(["sh", f"{D}/cp-spiboot.sh"], env=dict(os.environ, KEEP_CP_ON="1"), check=True,
               stdout=subprocess.DEVNULL)

# init_legacy_link() + link_start_normal_boot(): zero, queues 0, then the boot magic.
w32(0, 0); w32(4, 0)
for ht in (FMT_HT, RAW_HT):
    for i in range(4):
        w32(ht + i * 4, 0)
w32(0x400, 0); w32(0x404, 0)        # init_ctrl_msg(): ap2cp/cp2ap messages cleared
w32(0, MAGIC_BOOT); w32(4, 1)
print("IPC preparado: magic=%#x access=%d cp2ap_msg=%#x" % (r32(0), r32(4), r32(0x404)))

subprocess.run(["gpioset", "-p", "5ms", "-t", "0", "-c", "gpiochip12", "3=1"], check=True)
open("/sys/bus/platform/devices/13d20000.pcie/relink", "w").write("1")
db = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=DOORBELL & ~0xfff)
struct.pack_into("<I", db, DOORBELL & 0xfff, INT_PCIE_LINK_ACK)
print("link up, doorbell pcie_link_ack enviado; observando 6 s")

def raw_send_word(word):
    # Same frame as Scion hakios.shannon.c boot_send() (MIT-0): {0xFC, 215, 8, 0, word LE} on the RAW TX queue.
    frame = bytes([0xFC, 215, 8, 0]) + struct.pack("<I", word)
    head = r32(RAW_HT)
    for i, b in enumerate(frame):
        ipc[RAW_BUF + (head + i) % RAW_TXQ] = b
    w32(RAW_HT, (head + len(frame)) % RAW_TXQ)

ASK = int(os.environ.get("ASK", "0"), 0)
if ASK:
    time.sleep(0.2)
    raw_send_word(ASK)
    # pcie_send_ap2cp_irq(): set_ctrl_msg(ap2cp_msg @0x400, mask2int(MASK_SEND_RAW)) then the doorbell.
    w32(0x400, 0x80 | 0x01)
    struct.pack_into("<I", db, DOORBELL & 0xfff, INT_AP2CP_MSG)
    print("perguntado %#x na fila RAW TX + doorbell %d" % (ASK, INT_AP2CP_MSG))

last, t0 = None, time.monotonic()
while time.monotonic() - t0 < 6:
    st = (r32(0), r32(4), r32(0x404), r32(0x40c), str(queues()))
    if st != last:
        print("t=%5.2f s magic=%#x access=%d cp2ap_msg=%#x cp2ap_status=%#x q=%s" %
              ((time.monotonic() - t0,) + st))
        dump_rx("FMT", FMT_HT, FMT_BUF, FMT_TXQ, FMT_RXQ)
        dump_rx("RAW", RAW_HT, RAW_BUF, RAW_TXQ, RAW_RXQ)
        last = st
    time.sleep(0.01)
nz = sum(1 for b in ipc[:0x10000] if b)
print(f"bytes não zero nos primeiros 64 KiB do IPC: {nz}")
subprocess.run(["sh", f"{D}/modem-down.sh"])
