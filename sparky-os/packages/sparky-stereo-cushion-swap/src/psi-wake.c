// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wakes the Cushion Swap File the moment memory stalls, with the kernel's
// PSI trigger (Linux Documentation/accounting/psi.rst, "Monitoring for
// pressure thresholds"). Prints "ready" once the trigger is armed, then one
// "stall" line per event. Exit 2: no PSI here (no file, psi=0, trigger
// refused); exit 3: the trigger was lost.

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "/proc/pressure/memory";
	const char *trigger = argc > 2 ? argv[2] : "some 150000 1000000";
	struct pollfd fds = { .events = POLLPRI };

	// Stay resident: this is what must run when memory is short.
	mlockall(MCL_CURRENT | MCL_FUTURE);

	fds.fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (fds.fd < 0) {
		fprintf(stderr, "psi-wake: %s: %s\n", path, strerror(errno));
		return 2;
	}
	if (write(fds.fd, trigger, strlen(trigger) + 1) < 0) {
		fprintf(stderr, "psi-wake: trigger \"%s\" refused: %s\n", trigger, strerror(errno));
		return 2;
	}
	if (puts("ready") == EOF || fflush(stdout) == EOF)
		return 0;

	for (;;) {
		if (poll(&fds, 1, -1) < 0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "psi-wake: poll: %s\n", strerror(errno));
			return 3;
		}
		if (fds.revents & POLLERR) {
			fprintf(stderr, "psi-wake: trigger lost\n");
			return 3;
		}
		if ((fds.revents & POLLPRI) && (puts("stall") == EOF || fflush(stdout) == EOF))
			return 0;
	}
}
