#!/bin/sh
# Runs on the phone as root (needs libgpiod, spidev, kernel with patch 0140).
# Milestone 2: SPI-boot the Shannon S5123 BOOT section from the radio partition,
# as LineageOS cpboot_spi_load_cp_image() + power_on_cp(), then power the CP off.
set -u
# spidev may already be bound with the 4 KiB default buffer: reload it.
[ "$(cat /sys/module/spidev/parameters/bufsiz 2>/dev/null)" = 65536 ] || { modprobe -r spidev 2>/dev/null; modprobe spidev bufsiz=65536; }
[ "$(cat /sys/module/spidev/parameters/bufsiz)" = 65536 ] || { echo "spidev sem bufsiz=65536"; exit 1; }
[ -e /dev/spidev0.0 ] || { echo "sem /dev/spidev0.0"; ls /sys/bus/spi/devices/spi0.0/; exit 1; }

# radio TOC: BOOT at 0x320, size 0xfb90 (read-only)
dd if=/dev/sda15 of=/tmp/cp_boot.bin bs=1 skip=$((0x320)) count=$((0xfb90)) status=none
ls -l /tmp/cp_boot.bin

python3 - <<'EOF'
import mmap, os, struct, time
m = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
cmu = mmap.mmap(m, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x10700000)
sys = mmap.mmap(m, 0x2000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x10720000)
r = lambda mm, o: struct.unpack_from("<I", mm, o)[0]
def w(mm, o, v): struct.pack_into("<I", mm, o, v)
print("antes: mux=%#x div=%#x usi16_swconf=%#x" % (r(cmu, 0x690), r(cmu, 0x1820), r(sys, 0x1048)))
w(cmu, 0x690, r(cmu, 0x690) & ~(1 << 4))          # MUX_USER: OSC 26 MHz
for _ in range(100):
    if not r(cmu, 0x690) & (1 << 16): break
    time.sleep(0.001)
w(cmu, 0x1820, (r(cmu, 0x1820) & ~0xf) | 2)       # DIVRATIO=2 -> /3
for _ in range(100):
    if not r(cmu, 0x1820) & (1 << 16): break
    time.sleep(0.001)
print("depois: mux=%#x div=%#x" % (r(cmu, 0x690), r(cmu, 0x1820)))
EOF

out() { gpioset -p "${3:-1ms}" -t 0 -c "$1" "$2"; }
rd()  { gpioget -b pull-down --numeric -c "$1" "$2" 2>/dev/null; }
inputs() { echo "ps_hold=$(rd gpiochip52 0) cp2ap_wakeup=$(rd gpiochip51 0) phone_active=$(rd gpiochip49 0)"; }

echo "repouso: $(inputs)"
out gpiochip46 0=1          # pda_active = 1   (dump_noti gpp8-6 is SPI now: not touched)
out gpiochip30 0=0 50ms     # nreset = 0
out gpiochip41 0=1 50ms     # cp_pwr_on = 1
out gpiochip30 0=1 50ms     # nreset = 1
echo "ligado:  $(inputs)"

python3 - <<'EOF'
import os, time
img = open("/tmp/cp_boot.bin", "rb").read()
fd = os.open("/dev/spidev0.0", os.O_RDWR)
t = time.monotonic()
n = os.write(fd, img)          # one spi_sync, CS held for the whole image
print(f"SPI: {n}/{len(img)} bytes em {time.monotonic() - t:.3f} s")
os.close(fd)
EOF

last=""; i=0
while [ $i -lt 50 ]; do        # 5 s, like check_cp_status (200 x 20 ms = 4 s)
	cur=$(inputs)
	[ "$cur" != "$last" ] && echo "t=$((i * 100))ms  $cur"
	last=$cur; sleep 0.1; i=$((i + 1))
done
dmesg | grep -iE "spi|pcie" | tail -5
[ "${KEEP_CP_ON:-0}" = 1 ] && { echo "CP mantido ligado (KEEP_CP_ON=1)"; exit 0; }
out gpiochip30 0=0 10ms
out gpiochip41 0=0 10ms
out gpiochip46 0=0
echo "desligado: $(inputs)"
