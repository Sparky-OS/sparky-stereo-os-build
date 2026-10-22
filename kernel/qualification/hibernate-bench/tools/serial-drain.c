// SPDX-License-Identifier: GPL-2.0-or-later
/* Drain the guest result UART before shutting down the disposable VM. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <termios.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    if (argc != 2)
        return 2;
    int fd = open(argv[1], O_WRONLY | O_NOCTTY);
    if (fd < 0) {
        perror("serial-drain: open");
        return 1;
    }
    int rc;
    do {
        rc = tcdrain(fd);
    } while (rc < 0 && errno == EINTR);
    if (rc < 0)
        perror("serial-drain: tcdrain");
    close(fd);
    return rc < 0;
}
