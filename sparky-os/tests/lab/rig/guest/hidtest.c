/* hidtest.c (ORDER 22): a virtual HID joystick with 128 buttons, 8 axes and 4 hats, made through UHID in the guest, and
 * what the kernel's evdev node of it says. Static; run in the guest as root.
 *   hidtest        creates the device, sends a report with every button held, prints one line, keeps the device alive
 *                  and, when /tmp/sdl.open appears, sends the report again (a client that opened the device late).
 * The expected values are the descriptor's own: 128 buttons (usages 1 to 128), 8 axes (X to Dial), 4 hat switches. */
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uhid.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <dirent.h>

#ifndef EV_BTN
#define EV_BTN 0x06
#endif
#define MY_EVIOCGBTNCNT _IOR('E', 0x1c, unsigned int)

static unsigned char rd[] = {
	0x05, 0x01, 0x09, 0x04, 0xA1, 0x01,
	0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x33, 0x09, 0x34, 0x09, 0x35, 0x09, 0x36, 0x09, 0x37,
	0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x08, 0x81, 0x02,
	0x09, 0x39, 0x09, 0x39, 0x09, 0x39, 0x09, 0x39,
	0x15, 0x01, 0x25, 0x08, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95, 0x04, 0x81, 0x42,
	0x05, 0x09, 0x19, 0x01, 0x29, 0x80, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x80, 0x81, 0x02,
	0xC0};
#define NREP 26

static void send_report(int fd, int on)
{
	struct uhid_event ev;
	memset(&ev, 0, sizeof ev);
	ev.type = UHID_INPUT2;
	ev.u.input2.size = NREP;
	for (int i = 0; i < 8; i++)
		ev.u.input2.data[i] = 10 + 20 * i;
	ev.u.input2.data[8] = on ? 0x21 : 0x11;
	ev.u.input2.data[9] = on ? 0x43 : 0x11;
	memset(ev.u.input2.data + 10, on ? 0xFF : 0x00, 16);
	if (write(fd, &ev, sizeof ev) < 0)
		perror("uhid input");
}

static int bit(const unsigned char *b, int n) { return (b[n / 8] >> (n % 8)) & 1; }

static int find_event(char *path, size_t n)
{
	for (int i = 0; i < 64; i++) {
		char p[128], name[128] = "";
		snprintf(p, sizeof p, "/sys/class/input/event%d/device/name", i);
		int f = open(p, O_RDONLY);
		if (f < 0)
			continue;
		int r = read(f, name, sizeof name - 1);
		close(f);
		if (r > 0 && strstr(name, "Lab22 Pad")) {
			snprintf(path, n, "/dev/input/event%d", i);
			return 0;
		}
	}
	return -1;
}

int main(void)
{
	int fd = open("/dev/uhid", O_RDWR);
	if (fd < 0) {
		printf("LAB|hid|error|no /dev/uhid: %s\n", strerror(errno));
		return 2;
	}
	struct uhid_event ev;
	memset(&ev, 0, sizeof ev);
	ev.type = UHID_CREATE2;
	strcpy((char *)ev.u.create2.name, "Lab22 Pad");
	ev.u.create2.rd_size = sizeof rd;
	ev.u.create2.bus = 3;
	ev.u.create2.vendor = 0x1209;
	ev.u.create2.product = 0x0022;
	memcpy(ev.u.create2.rd_data, rd, sizeof rd);
	if (write(fd, &ev, sizeof ev) < 0) {
		printf("LAB|hid|error|UHID_CREATE2: %s\n", strerror(errno));
		return 2;
	}
	char path[64] = "";
	for (int t = 0; t < 50 && find_event(path, sizeof path); t++)
		usleep(100000);
	if (!path[0]) {
		printf("LAB|hid|error|the kernel made no event node for the device (HID layer or hid-generic missing?)\n");
		return 3;
	}
	usleep(300000);
	int ev_fd = open(path, O_RDONLY | O_NONBLOCK);
	if (ev_fd < 0) {
		printf("LAB|hid|error|open %s: %s\n", path, strerror(errno));
		return 3;
	}
	unsigned char types[8] = {0}, keys[96] = {0}, abs[8] = {0};
	ioctl(ev_fd, EVIOCGBIT(0, sizeof types), types);
	ioctl(ev_fd, EVIOCGBIT(EV_KEY, sizeof keys), keys);
	ioctl(ev_fd, EVIOCGBIT(EV_ABS, sizeof abs), abs);
	unsigned int btncnt = 0;
	int has_btn_ioctl = ioctl(ev_fd, MY_EVIOCGBTNCNT, &btncnt) == 0;
	int nkeys = 0, naxes = 0, nhats = 0;
	for (int c = 0x100; c < 0x300; c++)
		nkeys += bit(keys, c);
	for (int c = 0; c < 0x40; c++)
		if (bit(abs, c)) {
			if (c >= ABS_HAT0X && c <= ABS_HAT3Y)
				nhats++;
			else
				naxes++;
		}
	send_report(fd, 1);
	unsigned char seen_key[0x300 / 8 + 1] = {0};
	unsigned char seen_btn[512 / 8] = {0};
	struct pollfd pf = {ev_fd, POLLIN, 0};
	int dropped = 0;
	for (int t = 0; t < 10 && poll(&pf, 1, 300) > 0; t++) {
		struct input_event ie;
		while (read(ev_fd, &ie, sizeof ie) == sizeof ie) {
			if (ie.type == EV_KEY && ie.value == 1 && ie.code < 0x300)
				seen_key[ie.code / 8] |= 1 << (ie.code % 8);
			else if (ie.type == EV_BTN && ie.value == 1 && ie.code < 512)
				seen_btn[ie.code / 8] |= 1 << (ie.code % 8);
			else if (ie.type == EV_SYN && ie.code == SYN_DROPPED)
				dropped = 1;
		}
	}
	int pk = 0, pb = 0;
	for (int c = 0x100; c < 0x300; c++)
		pk += bit(seen_key, c);
	for (int c = 0; c < 512; c++)
		pb += bit(seen_btn, c);
	char absl[200] = "";
	for (int c = 0; c < 0x40; c++)
		if (bit(abs, c))
			snprintf(absl + strlen(absl), sizeof absl - strlen(absl), "%x,", c);
	int btn_type = bit(types, EV_BTN);
	int buttons = (has_btn_ioctl && btncnt) ? (int)btncnt : nkeys;
	int pressed = btn_type && pb ? pb : pk;
	printf("LAB|hid|kernel|device=%s|buttons=%d|key_codes=%d|ev_btn_type=%d|btncnt_ioctl=%d|axes=%d|hat_codes=%d|pressed=%d|syn_dropped=%d|abs_codes=%s\n",
	       path, buttons, nkeys, btn_type, has_btn_ioctl, naxes, nhats, pressed, dropped, absl);
	fflush(stdout);
	close(open("/tmp/hid.ready", O_CREAT | O_WRONLY, 0644));
	for (int t = 0; t < 600; t++) {
		if (access("/tmp/sdl.open", F_OK) == 0 && access("/tmp/hid.resent", F_OK) != 0) {
			send_report(fd, 0);
			usleep(100000);
			send_report(fd, 1);
			close(open("/tmp/hid.resent", O_CREAT | O_WRONLY, 0644));
		}
		usleep(100000);
	}
	return 0;
}
