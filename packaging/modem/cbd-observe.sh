#!/bin/sh
# Run Samsung's cbd once, unmodified, against cuse-umts and record the S5123 boot protocol.
# Root, on r8s with kernel 0140-0142. Read-only towards the phone's storage: system/vendor/APEX
# are loop-mounted ro, RADIO is only read, EFS is mounted ro and cbd gets a COPY in tmpfs.
set -u
L=/usr/local/lib/r8s-modem
R=/run/android
C=/run/android-root
TRACE=/run/cbd-trace.log
: > $TRACE

sh $L/modem-down.sh >/dev/null 2>&1
modprobe cuse
[ "$(cat /sys/module/spidev/parameters/bufsiz 2>/dev/null)" = 65536 ] || { modprobe -r spidev; modprobe spidev bufsiz=65536; }
# USI16 SPI clock: OSC 26 MHz / 3 -> 2.17 MHz SCLK (see cp-spiboot.sh / patch 0140).
python3 - <<'EOF'
import mmap, os, struct
m = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
c = mmap.mmap(m, 0x2000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x10700000)
r = lambda o: struct.unpack_from("<I", c, o)[0]
struct.pack_into("<I", c, 0x690, r(0x690) & ~(1 << 4))
struct.pack_into("<I", c, 0x1820, (r(0x1820) & ~0xf) | 2)
EOF

# Android chroot (idempotent)
mkdir -p $R/system $R/vendor $C
mountpoint -q $R/system || mount -o ro,noload "$(losetup -r -f --show -o $((1*1048576)) --sizelimit $((1124*1048576)) /dev/sda26)" $R/system
mountpoint -q $R/vendor || mount -o ro,noload "$(losetup -r -f --show -o $((5602*1048576)) --sizelimit $((353439*4096)) /dev/sda26)" $R/vendor
[ -f $R/runtime.img ] || python3 -c "import zipfile; open('$R/runtime.img','wb').write(zipfile.ZipFile('$R/system/system/apex/com.android.runtime.apex').read('apex_payload.img'))"
cd $C && mkdir -p system vendor dev proc apex/com.android.runtime mnt/vendor/efs data
mountpoint -q system || mount --bind $R/system/system system
mountpoint -q vendor || mount --bind $R/vendor vendor
mountpoint -q dev || mount --bind /dev dev
mountpoint -q proc || mount -t proc proc proc
mountpoint -q apex/com.android.runtime || mount -o ro,loop,noload $R/runtime.img apex/com.android.runtime
mountpoint -q data || mount -t tmpfs tmpfs data
# EFS: read-only mount, copy into a tmpfs for cbd
mkdir -p /run/efs-ro
mountpoint -q /run/efs-ro || mount -o ro,noload /dev/sda1 /run/efs-ro
mountpoint -q mnt/vendor/efs || mount -t tmpfs tmpfs mnt/vendor/efs
cp -a /run/efs-ro/. mnt/vendor/efs/
ls -l mnt/vendor/efs/nv_data.bin* 2>&1 | head -3
# cbd runs as the radio user: give it a COPY of RADIO (tmpfs), never the real partition.
mkdir -p /run/cbd-radio && mountpoint -q /run/cbd-radio || mount -t tmpfs -o size=80m tmpfs /run/cbd-radio
[ -s /run/cbd-radio/radio.img ] || dd if=/dev/sda15 of=/run/cbd-radio/radio.img bs=1M status=none
chown 1001:1001 /run/cbd-radio/radio.img
mkdir -p /dev/block/by-name && ln -sfn /run/cbd-radio/radio.img /dev/block/by-name/radio
mkdir -p $C/run/cbd-radio && { mountpoint -q $C/run/cbd-radio || mount --bind /run/cbd-radio $C/run/cbd-radio; }

for d in umts_boot0 umts_ramdump0; do
	$L/cuse-umts --devname=$d --trace=$TRACE &
done
for i in 1 2 3 4 5 6 7 8 9 10; do [ -e /dev/umts_boot0 ] && [ -e /dev/umts_ramdump0 ] && break; sleep 0.3; done
# cbd drops to the radio user (setuid/capset) before opening the boot device.
chmod 0666 /dev/umts_boot0 /dev/umts_ramdump0
ls -l /dev/umts_boot0 /dev/umts_ramdump0

install -m 0644 $L/cbd-props.so $C/data/cbd-props.so
echo "== cbd (90 s no máximo)"
LD_PRELOAD=/data/cbd-props.so timeout 90 chroot $C /system/bin/linker64 /vendor/bin/cbd -t s5100 -P by-name/radio -bs -me \
	-B umts_boot0 -D umts_ramdump0 -n /mnt/vendor/efs > /run/cbd-out.log 2>&1
echo "cbd rc=$?"
pkill -f "cuse-umts --devname" ; sleep 0.5
sh $L/modem-down.sh >/dev/null 2>&1
echo "== saída do cbd"; grep -vE "linkerconfig|ld.so: object" /run/cbd-out.log | uniq -c | tail -40
echo "== kmsg do cbd"; dmesg | grep "mif: cbd" | tail -40
echo "== trace"; tail -80 $TRACE
