// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * tpmcli: read, extend and reset a TPM 2.0 PCR through /dev/tpmrm0 (or /dev/tpm0), with no library.
 * Static, about 150 lines, meant for the bench's initramfs.
 *   tpmcli pcrread  <index>             prints the SHA-256 bank value as hex
 *   tpmcli pcrextend <index> <64 hex>   extends the SHA-256 bank (password session, empty auth)
 *   tpmcli pcrreset <index>             TPM2_PCR_Reset (only PCRs 16..23 are resettable)
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint8_t buf[4096];

static void put16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }
static void put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }

static int tpm_open(void)
{
	int fd = open("/dev/tpmrm0", O_RDWR);
	if (fd < 0)
		fd = open("/dev/tpm0", O_RDWR);
	return fd;
}

/* send cmd[0..len), read the response into buf, return the response size or -1 */
static int tpm_xfer(int fd, const uint8_t *cmd, size_t len)
{
	ssize_t n = write(fd, cmd, len);
	if (n != (ssize_t)len) {
		fprintf(stderr, "write: %s\n", strerror(errno));
		return -1;
	}
	n = read(fd, buf, sizeof(buf));
	if (n < 10) {
		fprintf(stderr, "short response (%zd)\n", n);
		return -1;
	}
	return (int)n;
}

static int hexval(int c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static size_t auth_area(uint8_t *p)
{
	/* TPMS_AUTH_COMMAND: TPM_RS_PW, empty nonce, no attributes, empty hmac */
	put32(p, 9);          /* authorizationSize */
	put32(p + 4, 0x40000009);
	put16(p + 8, 0);
	p[10] = 0;
	put16(p + 11, 0);
	return 13;
}

int main(int argc, char **argv)
{
	uint8_t cmd[512];
	size_t o;
	int fd, n;
	unsigned long idx;

	if (argc < 3) {
		fprintf(stderr, "usage: tpmcli pcrread|pcrextend|pcrreset <index> [digest-hex]\n");
		return 2;
	}
	idx = strtoul(argv[2], NULL, 10);
	if (idx > 23) {
		fprintf(stderr, "bad index\n");
		return 2;
	}
	fd = tpm_open();
	if (fd < 0) {
		fprintf(stderr, "no TPM device: %s\n", strerror(errno));
		return 1;
	}
	if (!strcmp(argv[1], "pcrread")) {
		put16(cmd, 0x8001); put32(cmd + 2, 20); put32(cmd + 6, 0x0000017e);
		put32(cmd + 10, 1);             /* count */
		put16(cmd + 14, 0x000b);        /* SHA-256 */
		cmd[16] = 3;                    /* sizeofSelect */
		cmd[17] = cmd[18] = cmd[19] = 0;
		cmd[17 + idx / 8] = 1 << (idx % 8);
		n = tpm_xfer(fd, cmd, 20);
		if (n < 0) return 1;
		if (get32(buf + 6)) { fprintf(stderr, "TPM rc 0x%x\n", get32(buf + 6)); return 1; }
		/* hdr 10, updateCounter 4, selection (4 count + 2 + 1 + 3), digests count 4, size 2, digest */
		o = 10 + 4 + 4 + 2 + 1 + 3 + 4 + 2;
		for (int i = 0; i < 32; i++) printf("%02x", buf[o + i]);
		printf("\n");
		return 0;
	}
	if (!strcmp(argv[1], "pcrextend")) {
		if (argc < 4 || strlen(argv[3]) != 64) { fprintf(stderr, "need 64 hex digits\n"); return 2; }
		put16(cmd, 0x8002); put32(cmd + 6, 0x00000182); put32(cmd + 10, idx);
		o = 14 + auth_area(cmd + 14);
		put32(cmd + o, 1); o += 4;      /* digests count */
		put16(cmd + o, 0x000b); o += 2;
		for (int i = 0; i < 32; i++) {
			int h = hexval(argv[3][2 * i]), l = hexval(argv[3][2 * i + 1]);
			if (h < 0 || l < 0) { fprintf(stderr, "bad hex\n"); return 2; }
			cmd[o++] = h << 4 | l;
		}
		put32(cmd + 2, o);
		n = tpm_xfer(fd, cmd, o);
		if (n < 0) return 1;
		if (get32(buf + 6)) { fprintf(stderr, "TPM rc 0x%x\n", get32(buf + 6)); return 1; }
		return 0;
	}
	if (!strcmp(argv[1], "pcrreset")) {
		put16(cmd, 0x8002); put32(cmd + 6, 0x0000013d); put32(cmd + 10, idx);
		o = 14 + auth_area(cmd + 14);
		put32(cmd + 2, o);
		n = tpm_xfer(fd, cmd, o);
		if (n < 0) return 1;
		if (get32(buf + 6)) { fprintf(stderr, "TPM rc 0x%x\n", get32(buf + 6)); return 1; }
		return 0;
	}
	fprintf(stderr, "unknown command %s\n", argv[1]);
	return 2;
}
