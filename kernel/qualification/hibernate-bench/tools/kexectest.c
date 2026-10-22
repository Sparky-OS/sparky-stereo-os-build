/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * kexectest: call kexec_load(2) and kexec_file_load(2) directly and print what the kernel answered. Static, no library
 * beyond libc. Used by the bench's "kexec" scenario (guest/phase-kexec.sh).
 *
 *   kexectest load0         kexec_load(0, 0, NULL, KEXEC_ARCH_DEFAULT). With no segments the call only unloads a staged
 *                           image, so it changes nothing when the kernel permits it; what matters is the answer.
 *   kexectest fload IMAGE [crash] [keep]
 *                           kexec_file_load(open(IMAGE), -1, 1, "", KEXEC_FILE_NO_INITRAMFS). When the kernel accepts the
 *                           image it is unloaded again at once (KEXEC_FILE_UNLOAD) unless "keep" is given; "crash" asks for a
 *                           panic (kdump) kernel instead of a reboot kernel. Nothing is ever executed.
 *
 * One line of output: op=<op> rc=<0|-1> errno=<n> name=<ERRNO NAME> msg=<strerror text>
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/kexec.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef KEXEC_FILE_UNLOAD
#define KEXEC_FILE_UNLOAD 0x00000001
#endif
#ifndef KEXEC_FILE_NO_INITRAMFS
#define KEXEC_FILE_NO_INITRAMFS 0x00000004
#endif

static const char *errname(int e)
{
	switch (e) {
	case 0: return "OK";
	case EPERM: return "EPERM";
	case EACCES: return "EACCES";
	case ENOENT: return "ENOENT";
	case ENOEXEC: return "ENOEXEC";
	case ENOMEM: return "ENOMEM";
	case EBUSY: return "EBUSY";
	case EINVAL: return "EINVAL";
	case ENOSYS: return "ENOSYS";
	case EBADMSG: return "EBADMSG";
	case ENOKEY: return "ENOKEY";
	case EKEYEXPIRED: return "EKEYEXPIRED";
	case EKEYREVOKED: return "EKEYREVOKED";
	case EKEYREJECTED: return "EKEYREJECTED";
	case ENODATA: return "ENODATA";
	case E2BIG: return "E2BIG";
	case EFAULT: return "EFAULT";
	default: return "E?";
	}
}

static void report(const char *op, long rc)
{
	int e = rc < 0 ? errno : 0;

	printf("op=%s rc=%d errno=%d name=%s msg=%s\n", op, rc < 0 ? -1 : 0, e, errname(e), e ? strerror(e) : "accepted");
	fflush(stdout);
}

int main(int argc, char **argv)
{
	long rc;

	if (argc == 2 && !strcmp(argv[1], "load0")) {
		rc = syscall(SYS_kexec_load, 0UL, 0UL, NULL, (unsigned long)KEXEC_ARCH_DEFAULT);
		report("kexec_load", rc);
		return 0;
	}
	if (argc >= 3 && !strcmp(argv[1], "fload")) {
		int crash = 0, keep = 0, i;
		unsigned long flags = KEXEC_FILE_NO_INITRAMFS;
		int fd;

		for (i = 3; i < argc; i++) {
			if (!strcmp(argv[i], "crash"))
				crash = 1;
			else if (!strcmp(argv[i], "keep"))
				keep = 1;
		}
		if (crash)
			flags |= KEXEC_FILE_ON_CRASH;
		fd = open(argv[2], O_RDONLY | O_CLOEXEC);

		if (fd < 0) {
			printf("op=kexec_file_load rc=-1 errno=%d name=%s msg=cannot open %s: %s\n", errno, errname(errno), argv[2], strerror(errno));
			return 0;
		}
		rc = syscall(SYS_kexec_file_load, fd, -1, 1UL, "", flags);
		report(crash ? "kexec_file_load_crash" : "kexec_file_load", rc);
		if (rc == 0 && !keep) {
			long u = syscall(SYS_kexec_file_load, -1, -1, 0UL, NULL, (unsigned long)KEXEC_FILE_UNLOAD | (crash ? KEXEC_FILE_ON_CRASH : 0));

			printf("unload=%s\n", u == 0 ? "ok" : strerror(errno));
		}
		close(fd);
		return 0;
	}
	fprintf(stderr, "usage: kexectest load0 | kexectest fload IMAGE [crash] [keep]\n");
	return 2;
}
