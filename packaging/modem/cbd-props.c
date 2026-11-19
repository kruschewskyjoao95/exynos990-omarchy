// SPDX-License-Identifier: GPL-2.0
/*
 * cbd-props: LD_PRELOAD for Samsung's cbd inside the Android chroot on r8s, where no Android
 * property service exists. Overrides libcutils property_get/property_get_int32/property_set,
 * answers from a small table and logs every access to stderr. Freestanding (no libc), so the
 * same object loads under bionic. Build:
 *   gcc -O2 -fPIC -shared -nostdlib -fno-stack-protector -o cbd-props.so cbd-props.c
 */
typedef unsigned long size_t;

static long sys_write(int fd, const void *buf, size_t n)
{
	register long x0 __asm__("x0") = fd;
	register long x1 __asm__("x1") = (long)buf;
	register long x2 __asm__("x2") = (long)n;
	register long x8 __asm__("x8") = 64;	/* __NR_write */

	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x8) : "memory");
	return x0;
}

static size_t slen(const char *s) { size_t n = 0; while (s && s[n]) n++; return n; }
static int seq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static void say(const char *a, const char *b, const char *c)
{
	sys_write(2, a, slen(a)); sys_write(2, b, slen(b)); sys_write(2, c, slen(c)); sys_write(2, "\n", 1);
}

/* Values an Android boot would have provided before cpboot-daemon runs. */
static const char *const table[][2] = {
	{ "vendor.cbd.rfs_check_done", "1" },	/* rfsd finished checking EFS */
	{ "ro.hardware.chipname", "exynos9830" },
	{ 0, 0 },
};

int property_get(const char *key, char *value, const char *def)
{
	const char *v = def;
	size_t n, i;
	int hit = 0;

	for (i = 0; table[i][0]; i++)
		if (seq(key, table[i][0])) {
			v = table[i][1];
			hit = 1;
		}
	if (!v)
		v = "";
	n = slen(v);
	if (n > 91)
		n = 91;
	for (i = 0; i < n; i++)
		value[i] = v[i];
	value[n] = 0;
	say("cbd-props: get ", key, hit ? " -> table" : " -> default");
	say("cbd-props:   = ", value, "");
	return (int)n;
}

int property_get_int32(const char *key, int def)
{
	char buf[92];
	int n = property_get(key, buf, 0), v = 0, i, neg = buf[0] == '-';

	if (n <= 0)
		return def;
	for (i = neg; buf[i] >= '0' && buf[i] <= '9'; i++)
		v = v * 10 + buf[i] - '0';
	return neg ? -v : v;
}

int property_set(const char *key, const char *value)
{
	say("cbd-props: SET ", key, value);
	return 0;
}
