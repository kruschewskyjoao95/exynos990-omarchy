// SPDX-License-Identifier: GPL-2.0
/*
 * cuse-umts: a userspace /dev/umts_boot0 (and umts_ramdump0) for the Shannon S5123 on r8s.
 *
 * Purpose: run Samsung's own cbd once, unmodified, and record every message of its boot
 * protocol ("STD UDL") so an open loader can replace it. Each ioctl/read/write does what
 * LineageOS cpif (97369af7) does for an S5100-type modem on a PCIe link:
 *   POWER_ON/RESET   power_on_cp(): pda_active=1, nreset=0, cp_pwr_on=1, nreset=1 (GPIO)
 *   LOAD_CP_IMAGE    cpboot_spi_load_cp_image(): one spi_sync of img.size bytes (spidev)
 *   START_CP_BOOT    start_normal_boot(): ctrl msgs cleared, legacy queues zeroed, magic "BOOT",
 *                    check_cp_status() (CP2AP_WAKEUP), s5100_poweron_pcie() (AP2CP_WAKEUP, relink)
 *   write()          bootdump_write(): SIPC5 frame (0xF8|pad, ch 215, len16 incl. header, padded
 *                    to 4) on the legacy RAW TX queue, then pcie_send_ap2cp_irq(): ap2cp_msg =
 *                    mask2int(MASK_SEND_RAW) and the doorbell with int_ap2cp_msg
 *   read()/poll()    frames from the legacy RAW RX queue (polled), header stripped
 *   REQ_SECURITY     -EINVAL (security_req is NULL for LINKDEV_PCIE)
 * Everything is logged as hex to the trace file.
 *
 * Build: gcc -O2 -Wall -o cuse-umts cuse-umts.c $(pkg-config --cflags --libs fuse3) -lpthread
 * Run:   cuse-umts -f --devname=umts_boot0 --trace=/run/cbd-trace.log
 */
#define FUSE_USE_VERSION 31
#include <cuse_lowlevel.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define IPC_BASE	0xF0000000UL
#define IPC_SIZE	0x800000UL
#define DOORBELL	0x14060000UL	/* bus 0x14d60000 (pci_db_addr): the only address the CP answers */
#define RAW_HT		0x18		/* txq head, tail, rxq head, tail */
#define RAW_BUF		0x3000
#define RAW_TXQ		0x1FD000
#define RAW_RXQ		0x200000
#define FMT_HT		0x8
#define AP2CP_MSG	0x400
#define CP2AP_MSG	0x404
#define MAGIC_BOOT	0x424F4F54u
#define CH_BOOT		215
#define CH_DUMP		225
#define INT_AP2CP_MSG	(0x10000 | 0)	/* int_ap2cp_msg 0 + DOORBELL_INT_ADD (cpif include/legacy.h) */
#define MASK_SEND_RAW_IRQ (0x80 | 0x01)
#define PCIE_MSI_ADDR_LO 0x820
#define PCIE_MSI_ADDR_HI 0x824
#define CP_MSI_ADDR	0xf6200000u

enum { ST_OFFLINE, ST_CRASH_RESET, ST_CRASH_EXIT, ST_BOOTING, ST_ONLINE };

static volatile uint8_t *ipc;
static volatile uint32_t *doorbell;
static volatile uint8_t *dbi, *sysreg;	/* 0x13800000 (GEN4_1 DBI), 0x13c20000 (SYSREG_HSI2) */
static int spi_fd = -1;
static FILE *trace;
static int channel = CH_BOOT;
static int state = ST_OFFLINE;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct fuse_pollhandle *pending_ph;

static void tlog(const char *fmt, ...)
{
	struct timespec ts;
	va_list ap;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	fprintf(trace, "[%5ld.%03ld] ", ts.tv_sec, ts.tv_nsec / 1000000);
	va_start(ap, fmt);
	vfprintf(trace, fmt, ap);
	va_end(ap);
	fflush(trace);
}

static void thex(const char *what, const uint8_t *p, size_t n)
{
	size_t i, show = n < 256 ? n : 256;

	tlog("%s %zu B:", what, n);
	for (i = 0; i < show; i++)
		fprintf(trace, " %02x", p[i]);
	fprintf(trace, n > show ? " ...\n" : "\n");
	fflush(trace);
}

static uint32_t r32(unsigned long o) { return *(volatile uint32_t *)(ipc + o); }
static void w32(unsigned long o, uint32_t v) { *(volatile uint32_t *)(ipc + o) = v; __sync_synchronize(); }

static int sh(const char *cmd)
{
	int ret = system(cmd);

	tlog("  sh: %s -> %d\n", cmd, ret);
	return ret;
}

static int gpio_get(const char *chip)
{
	char cmd[128];
	FILE *p;
	int v = -1;

	snprintf(cmd, sizeof(cmd), "gpioget -b pull-down --numeric -c %s 0", chip);
	p = popen(cmd, "r");
	if (p) {
		if (fscanf(p, "%d", &v) != 1)
			v = -1;
		pclose(p);
	}
	return v;
}

static void power_on_cp(void)
{
	sh("gpioset -p 1ms -t 0 -c gpiochip46 0=1");	/* pda_active */
	sh("gpioset -p 50ms -t 0 -c gpiochip30 0=0");	/* nreset low */
	sh("gpioset -p 50ms -t 0 -c gpiochip41 0=1");	/* cp_pwr_on */
	sh("gpioset -p 50ms -t 0 -c gpiochip30 0=1");	/* nreset high */
	state = ST_OFFLINE;
}

static void power_off_cp(void)
{
	sh("sh /usr/local/lib/r8s-modem/modem-down.sh >/dev/null");
	state = ST_OFFLINE;
}

/* Bytes waiting in the RAW RX queue (CP writes head, we own tail). */
static uint32_t rx_avail(void)
{
	uint32_t head = r32(RAW_HT + 8), tail = r32(RAW_HT + 12);

	if (head >= RAW_RXQ || tail >= RAW_RXQ)
		return 0;
	return (head + RAW_RXQ - tail) % RAW_RXQ;
}

static uint8_t rx_byte(uint32_t tail, uint32_t i)
{
	return ipc[RAW_BUF + RAW_TXQ + (tail + i) % RAW_RXQ];
}

static int start_normal_boot(void)
{
	int i;

	w32(0, 0); w32(4, 0);
	for (i = 0; i < 4; i++) {
		w32(FMT_HT + i * 4, 0);
		w32(RAW_HT + i * 4, 0);
	}
	w32(AP2CP_MSG, 0); w32(CP2AP_MSG, 0);
	w32(0, MAGIC_BOOT); w32(4, 1);
	state = ST_BOOTING;
	for (i = 0; i < 200 && gpio_get("gpiochip51") != 1; i++)	/* check_cp_status(mc, 200) */
		usleep(20000);
	tlog("  check_cp_status: CP2AP_WAKEUP=%d after %d x 20 ms\n", gpio_get("gpiochip51"), i);
	if (i == 200)
		return -EFAULT;
	sh("gpioset -p 5ms -t 0 -c gpiochip12 3=1");		/* AP2CP_WAKEUP */
	if (sh("echo 1 > /sys/bus/platform/devices/13d20000.pcie/relink"))
		return -EIO;
	/* The root port must master too, or the CP's reads/writes of AP memory stop at the bridge. */
	if (sh("setpci -s 0001:00:00.0 COMMAND=0x0006:0x0006"))
		return -EIO;
	/* exynos_pcie_rc_set_iocc(1) for the 9830 HSI2 block (use-cache-coherency in LineageOS):
	 * DBI COHERENCY_CONTROL_3 (0x8e8) = 0x10101010, SYSREG_HSI2 SHARABILITY_CTRL (0x704) |= 3. */
	*(volatile uint32_t *)(dbi + 0x8e8) = 0x10101010;
	*(volatile uint32_t *)(sysreg + 0x704) = (*(volatile uint32_t *)(sysreg + 0x704) & ~3u) | 3u;
	tlog("  IOCC: dbi 0x8e8=%#x sysreg 0x704=%#x\n", *(volatile uint32_t *)(dbi + 0x8e8),
	     *(volatile uint32_t *)(sysreg + 0x704));
	/* s51xx_pcie_probe(): BAR0 = pci_db_addr exactly; the CP decodes only around it. */
	if (sh("setpci -s 0001:01:00.0 BASE_ADDRESS_0=0x14d60000 BASE_ADDRESS_1=0"))
		return -EIO;
	/* The CP needs MSI configured even when the host polls the RX queue. */
	*(volatile uint32_t *)(dbi + PCIE_MSI_ADDR_LO) = CP_MSI_ADDR;
	*(volatile uint32_t *)(dbi + PCIE_MSI_ADDR_HI) = 0;
	return sh("setpci -s 0001:01:00.0 CAP_MSI+4.L=f6200000 CAP_MSI+8.W=0000 CAP_MSI+2.W=0021:0071")
		? -EIO : 0;
}

static void u_open(fuse_req_t req, struct fuse_file_info *fi)
{
	tlog("open flags=%#x\n", fi->flags);
	fuse_reply_open(req, fi);
}

static void u_release(fuse_req_t req, struct fuse_file_info *fi)
{
	tlog("close\n");
	fuse_reply_err(req, 0);
}

/* SIPC5 aligns padded frames to the target kernel's 64-bit word size. */
static uint32_t sipc5_padding(uint32_t len)
{
	return (8 - len % 8) % 8;
}

static void u_write(fuse_req_t req, const char *buf, size_t size, off_t off, struct fuse_file_info *fi)
{
	uint32_t len = size + 4, pad = sipc5_padding(len), head, i;
	uint8_t hdr[4] = { 0xF8 | 0x04, (uint8_t)channel, (uint8_t)len, (uint8_t)(len >> 8) };

	if (size == 4)
		thex("AP->CP write", (const uint8_t *)buf, size);
	else
		tlog("AP->CP write %zu B\n", size);
	if (len > 0xFFFF) {
		tlog("  frame too long for a 16-bit SIPC5 length\n");
		fuse_reply_err(req, EMSGSIZE);
		return;
	}
	pthread_mutex_lock(&lock);
	head = r32(RAW_HT);
	for (i = 0; i < len + pad; i++) {
		uint8_t b = i < 4 ? hdr[i] : i < len ? (uint8_t)buf[i - 4] : 0;

		ipc[RAW_BUF + (head + i) % RAW_TXQ] = b;
	}
	__sync_synchronize();
	w32(RAW_HT, (head + len + pad) % RAW_TXQ);
	w32(AP2CP_MSG, MASK_SEND_RAW_IRQ);
	*doorbell = INT_AP2CP_MSG;
	__sync_synchronize();
	pthread_mutex_unlock(&lock);
	tlog("  framed %u+%u B at txq head %u; ap2cp_msg=%#x doorbell %d (txq tail %u)\n", len, pad, head,
	     MASK_SEND_RAW_IRQ, INT_AP2CP_MSG, r32(RAW_HT + 4));
	fuse_reply_write(req, size);
}

static void u_read(fuse_req_t req, size_t size, off_t off, struct fuse_file_info *fi)
{
	uint8_t *out;
	uint32_t tail, len, pad, hl = 4, i;

	for (;;) {
		pthread_mutex_lock(&lock);
		if (rx_avail() >= 4)
			break;
		pthread_mutex_unlock(&lock);
		if (fi->flags & O_NONBLOCK) {
			fuse_reply_err(req, EAGAIN);
			return;
		}
		usleep(1000);
	}
	tail = r32(RAW_HT + 12);
	len = rx_byte(tail, 2) | rx_byte(tail, 3) << 8;
	if ((rx_byte(tail, 0) & 0xF8) != 0xF8 || len < hl || len > rx_avail()) {
		tlog("  RX: bad frame header %02x %02x %02x %02x (avail %u): dropping queue\n", rx_byte(tail, 0),
		     rx_byte(tail, 1), rx_byte(tail, 2), rx_byte(tail, 3), rx_avail());
		w32(RAW_HT + 12, r32(RAW_HT + 8));
		pthread_mutex_unlock(&lock);
		fuse_reply_err(req, EIO);
		return;
	}
	pad = (rx_byte(tail, 0) & 0x04) ? sipc5_padding(len) : 0;
	out = malloc(len);
	for (i = 0; i < len; i++)
		out[i] = rx_byte(tail, i);
	w32(RAW_HT + 12, (tail + len + pad) % RAW_RXQ);
	pthread_mutex_unlock(&lock);
	tlog("CP->AP frame cfg=%#x ch=%u len=%u\n", out[0], out[1], len);
	thex("CP->AP read", out + hl, len - hl);
	fuse_reply_buf(req, (char *)out + hl, (len - hl) < size ? (len - hl) : size);
	free(out);
}

static void u_poll(fuse_req_t req, struct fuse_file_info *fi, struct fuse_pollhandle *ph)
{
	unsigned rev = POLLOUT | POLLWRNORM;

	pthread_mutex_lock(&lock);
	if (rx_avail() >= 4)
		rev |= POLLIN | POLLRDNORM;
	if (ph) {
		if (pending_ph)
			fuse_pollhandle_destroy(pending_ph);
		pending_ph = ph;
	}
	pthread_mutex_unlock(&lock);
	fuse_reply_poll(req, rev);
}

static void *rx_watch(void *unused)
{
	for (;;) {
		pthread_mutex_lock(&lock);
		if (pending_ph && rx_avail() >= 4) {
			fuse_lowlevel_notify_poll(pending_ph);
			fuse_pollhandle_destroy(pending_ph);
			pending_ph = NULL;
		}
		pthread_mutex_unlock(&lock);
		usleep(1000);
	}
	return NULL;
}

/* struct cp_image (modem_prj.h): u64 binary; u32 size, m_offset, b_offset, mode, len; packed */
struct cp_image { uint64_t binary; uint32_t size, m_offset, b_offset, mode, len; } __attribute__((packed));

static void u_ioctl(fuse_req_t req, int scmd, void *arg, struct fuse_file_info *fi, unsigned flags,
		    const void *in, size_t in_sz, size_t out_sz)
{
	unsigned cmd = (unsigned)scmd, dir = _IOC_DIR(cmd), sz = _IOC_SIZE(cmd), nr = _IOC_NR(cmd);
	struct iovec iv[2];
	int ret = 0;

	if (_IOC_TYPE(cmd) != 'o') {
		tlog("ioctl %#x: not ours\n", cmd);
		fuse_reply_err(req, ENOTTY);
		return;
	}
	/* Unrestricted CUSE ioctl: ask the kernel to copy the argument struct in/out first. */
	if (((dir & _IOC_WRITE) && in_sz < sz) || ((dir & _IOC_READ) && out_sz < sz)) {
		iv[0].iov_base = arg;
		iv[0].iov_len = sz;
		fuse_reply_ioctl_retry(req, (dir & _IOC_WRITE) ? iv : NULL, (dir & _IOC_WRITE) ? 1 : 0,
				       (dir & _IOC_READ) ? iv : NULL, (dir & _IOC_READ) ? 1 : 0);
		return;
	}

	switch (nr) {
	case 0x19:	/* IOCTL_POWER_ON */
		tlog("ioctl POWER_ON\n");
		power_on_cp();
		break;
	case 0x20:	/* IOCTL_POWER_OFF */
		tlog("ioctl POWER_OFF\n");
		power_off_cp();
		break;
	case 0x21:	/* IOCTL_POWER_RESET (struct boot_mode) */
		tlog("ioctl POWER_RESET mode=%u\n", *(const uint32_t *)in);
		power_on_cp();
		break;
	case 0x22:	/* IOCTL_START_CP_BOOTLOADER (struct boot_mode) */
		tlog("ioctl START_CP_BOOTLOADER mode=%u\n", *(const uint32_t *)in);
		ret = start_normal_boot();
		break;
	case 0x23:	/* IOCTL_COMPLETE_NORMAL_BOOTUP */
		tlog("ioctl COMPLETE_NORMAL_BOOTUP (cp2ap_msg %#x)\n", r32(CP2AP_MSG));
		state = ST_ONLINE;
		break;
	case 0x27:	/* IOCTL_GET_CP_STATUS: the state is the return value */
		tlog("ioctl GET_CP_STATUS -> %d\n", state);
		fuse_reply_ioctl(req, state, NULL, 0);
		return;
	case 0x40: {	/* IOCTL_LOAD_CP_IMAGE */
		const struct cp_image *img = in;

		if (in_sz == sizeof(*img)) {
			tlog("ioctl LOAD_CP_IMAGE binary=%#llx size=%u m_off=%#x b_off=%#x mode=%u len=%u\n",
			     (unsigned long long)img->binary, img->size, img->m_offset, img->b_offset, img->mode,
			     img->len);
			iv[0].iov_base = arg;
			iv[0].iov_len = sizeof(*img);
			iv[1].iov_base = (void *)(uintptr_t)img->binary;
			iv[1].iov_len = img->size;
			fuse_reply_ioctl_retry(req, iv, 2, NULL, 0);
			return;
		}
		thex("  image head", (const uint8_t *)in + sizeof(*img), 32);
		ret = write(spi_fd, (const uint8_t *)in + sizeof(*img), in_sz - sizeof(*img));
		tlog("  SPI write %zu B -> %d\n", in_sz - sizeof(*img), ret);
		ret = ret == (int)(in_sz - sizeof(*img)) ? 0 : -EIO;
		break;
	}
	case 0x53:	/* IOCTL_REQ_SECURITY */
		tlog("ioctl REQ_SECURITY mode=%u p2=%#x p3=%#x -> EINVAL (no security_req on PCIe)\n",
		     ((const uint32_t *)in)[0], ((const uint32_t *)in)[1], ((const uint32_t *)in)[2]);
		fuse_reply_err(req, EINVAL);
		return;
	default:
		tlog("ioctl nr %#x dir %u size %u: answered with zeros\n", nr, dir, sz);
		if (dir & _IOC_READ) {
			void *z = calloc(1, sz);

			fuse_reply_ioctl(req, 0, z, sz);
			free(z);
			return;
		}
	}
	if (ret < 0)
		fuse_reply_err(req, -ret);
	else
		fuse_reply_ioctl(req, ret, NULL, 0);
}

static const struct cuse_lowlevel_ops ops = {
	.open = u_open,
	.release = u_release,
	.read = u_read,
	.write = u_write,
	.ioctl = u_ioctl,
	.poll = u_poll,
};

int main(int argc, char **argv)
{
	const char *devname = "umts_boot0", *trace_path = "/run/cbd-trace.log";
	char devarg[64];
	const char *dev_info_argv[] = { devarg };
	struct cuse_info ci = { 0 };
	char *fargv[8];
	int fargc = 0, i, mem;
	pthread_t th;

	for (i = 1; i < argc; i++) {
		if (!strncmp(argv[i], "--devname=", 10))
			devname = argv[i] + 10;
		else if (!strncmp(argv[i], "--trace=", 8))
			trace_path = argv[i] + 8;
	}
	if (!strcmp(devname, "umts_ramdump0"))
		channel = CH_DUMP;
	trace = fopen(trace_path, "a");
	if (!trace)
		return 1;
	mem = open("/dev/mem", O_RDWR | O_SYNC);
	if (mem < 0)
		return 1;
	ipc = mmap(NULL, IPC_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, mem, IPC_BASE);
	doorbell = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, mem, DOORBELL & ~0xfffUL);
	dbi = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, mem, 0x13800000UL);
	sysreg = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, mem, 0x13c20000UL);
	if (ipc == MAP_FAILED || doorbell == MAP_FAILED || dbi == MAP_FAILED || sysreg == MAP_FAILED)
		return 1;
	doorbell = (volatile uint32_t *)((volatile uint8_t *)doorbell + (DOORBELL & 0xfff));
	spi_fd = open("/dev/spidev0.0", O_RDWR);
	tlog("cuse-umts %s (ch %d) up; spidev fd %d\n", devname, channel, spi_fd);

	snprintf(devarg, sizeof(devarg), "DEVNAME=%s", devname);
	ci.dev_info_argc = 1;
	ci.dev_info_argv = dev_info_argv;
	ci.flags = CUSE_UNRESTRICTED_IOCTL;
	fargv[fargc++] = argv[0];
	fargv[fargc++] = "-f";
	pthread_create(&th, NULL, rx_watch, NULL);
	return cuse_lowlevel_main(fargc, fargv, &ci, &ops, NULL);
}
