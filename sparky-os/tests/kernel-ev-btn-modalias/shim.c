// SPDX-License-Identifier: GPL-2.0-only
/*
 * ORDER 664: a user-space shim for the modalias functions of drivers/input/input.c, which are included unchanged
 * (FUNCTIONS). It gives them the kernel's names with the kernel's meaning: snprintf() has vsnprintf()'s size check
 * (lib/vsprintf.c: a size above INT_MAX warns and returns 0), max() and the bitmap walk are the kernel's.
 */
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define BITS_PER_LONG (8 * (int)sizeof(long))
#define BITS_TO_LONGS(n) (((n) + BITS_PER_LONG - 1) / BITS_PER_LONG)
#define max(a, b) ((a) > (b) ? (a) : (b))
/* include/uapi/linux/input-event-codes.h and input.h of the tree (7.3.4 with the EV_BTN series) */
#define EV_MAX 0x1f
#define KEY_MAX 0x2ff
#define KEY_MIN_INTERESTING 113 /* KEY_MUTE */
#define REL_MAX 0x0f
#define ABS_MAX 0x3f
#define MSC_MAX 0x07
#define LED_MAX 0x0f
#define SND_MAX 0x07
#define FF_MAX 0x7f
#define SW_MAX 0x10

struct input_id { unsigned short bustype, vendor, product, version; };
struct input_dev {
	struct input_id id;
	unsigned long evbit[BITS_TO_LONGS(EV_MAX + 1)], keybit[BITS_TO_LONGS(KEY_MAX + 1)], relbit[BITS_TO_LONGS(REL_MAX + 1)];
	unsigned long absbit[BITS_TO_LONGS(ABS_MAX + 1)], mscbit[BITS_TO_LONGS(MSC_MAX + 1)], ledbit[BITS_TO_LONGS(LED_MAX + 1)];
	unsigned long sndbit[BITS_TO_LONGS(SND_MAX + 1)], ffbit[BITS_TO_LONGS(FF_MAX + 1)], swbit[BITS_TO_LONGS(SW_MAX + 1)];
	unsigned int button_count;
};

static int test_bit(int nr, const unsigned long *map) { return (map[nr / BITS_PER_LONG] >> (nr % BITS_PER_LONG)) & 1; }
static void set_bit(int nr, unsigned long *map) { map[nr / BITS_PER_LONG] |= 1UL << (nr % BITS_PER_LONG); }
#define for_each_set_bit_from(bit, map, size) for (; (bit) < (int)(size); (bit)++) if (test_bit((bit), (map)))

static int warnings;
/* the kernel's snprintf(): vsnprintf() rejects a size above INT_MAX with WARN_ON_ONCE and returns 0 */
static int kernel_snprintf(char *buf, size_t size, const char *fmt, ...)
{
	va_list args;
	int n;

	if (size > INT_MAX) {
		warnings++;
		return 0;
	}
	va_start(args, fmt);
	n = vsnprintf(buf, size, fmt, args);
	va_end(args);
	return n;
}
#define snprintf kernel_snprintf
#include FUNCTIONS
#undef snprintf

static int prove(unsigned int buttons)
{
	static char buf[4096];
	struct input_dev dev = { .id = { 3, 0x044f, 0xb10a, 0x0111 }, .button_count = buttons };
	int measured, printed;

	set_bit(1, dev.evbit); set_bit(3, dev.evbit); set_bit(6, dev.evbit);
	for (int key = 0x120; key < 0x130; key++)
		set_bit(key, dev.keybit);
	set_bit(0, dev.absbit); set_bit(1, dev.absbit);
	warnings = 0;
	measured = input_print_modalias_parts(NULL, 0, 0, &dev);
	printed = input_print_modalias(buf, sizeof(buf), &dev);
	printf("buttons %u: warnings %d measured %d printed %d (%s)\n", buttons, warnings, measured, printed, buf);
	return warnings == 0 && measured == printed && printed == (int)strlen(buf);
}

int main(void)
{
	int ok = prove(1) & prove(128);

	puts(ok ? "PASS the measuring pass does not warn and measures what is printed"
		: "FAIL the measuring pass warns in vsnprintf() or measures a shorter modalias");
	return !ok;
}
