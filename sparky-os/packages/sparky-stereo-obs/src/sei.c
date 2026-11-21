/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
#include "sei.h"

#include <stdlib.h>
#include <string.h>

struct bits {
	const uint8_t *data;
	size_t size;
	size_t pos; /* in bits */
};

static int read_bit(struct bits *b)
{
	if (b->pos >= b->size * 8)
		return -1;
	int bit = (b->data[b->pos / 8] >> (7 - b->pos % 8)) & 1;
	b->pos++;
	return bit;
}

static long read_bits(struct bits *b, int count)
{
	long value = 0;
	for (int i = 0; i < count; i++) {
		int bit = read_bit(b);
		if (bit < 0)
			return -1;
		value = value << 1 | bit;
	}
	return value;
}

/* ue(v), H.264 9.1 */
static long read_ue(struct bits *b)
{
	int zeros = 0;
	for (;;) {
		int bit = read_bit(b);
		if (bit < 0 || zeros > 31)
			return -1;
		if (bit)
			break;
		zeros++;
	}
	long rest = read_bits(b, zeros);
	return rest < 0 ? -1 : (1L << zeros) - 1 + rest;
}

static int parse_packing(const uint8_t *payload, size_t size, struct stereo_sei_packing *out)
{
	struct bits b = {payload, size, 0};
	if (read_ue(&b) < 0) /* frame_packing_arrangement_id */
		return 0;
	long cancel = read_bits(&b, 1);
	if (cancel < 0)
		return 0;
	memset(out, 0, sizeof(*out));
	out->cancel = (int)cancel;
	if (cancel)
		return 1;
	long type = read_bits(&b, 7);
	long quincunx = read_bits(&b, 1);
	long interpretation = read_bits(&b, 6);
	if (type < 0 || quincunx < 0 || interpretation < 0)
		return 0;
	out->type = (int)type;
	out->quincunx = (int)quincunx;
	out->interpretation = (int)interpretation;
	return 1;
}

/* The SEI messages of one RBSP (H.264 7.3.2.3, H.265 7.3.5): payloadType and payloadSize as runs of 0xFF bytes. */
static int scan_sei_rbsp(const uint8_t *rbsp, size_t size, struct stereo_sei_packing *out)
{
	size_t i = 0;
	while (i < size && !(rbsp[i] == 0x80 && i + 1 == size)) {
		unsigned type = 0, length = 0;
		while (i < size && rbsp[i] == 0xFF) {
			type += 255;
			i++;
		}
		if (i >= size)
			return 0;
		type += rbsp[i++];
		while (i < size && rbsp[i] == 0xFF) {
			length += 255;
			i++;
		}
		if (i >= size)
			return 0;
		length += rbsp[i++];
		if (length > size - i)
			return 0;
		if (type == 45)
			return parse_packing(rbsp + i, length, out);
		i += length;
	}
	return 0;
}

static int scan_nal(const uint8_t *nal, size_t size, enum stereo_sei_codec codec, struct stereo_sei_packing *out)
{
	size_t header = codec == STEREO_SEI_HEVC ? 2 : 1;
	if (size <= header)
		return 0;
	int nal_type = codec == STEREO_SEI_HEVC ? (nal[0] >> 1) & 0x3F : nal[0] & 0x1F;
	if ((codec == STEREO_SEI_H264 && nal_type != 6) || (codec == STEREO_SEI_HEVC && nal_type != 39))
		return 0;
	uint8_t *rbsp = malloc(size);
	if (!rbsp)
		return 0;
	size_t n = 0, zeros = 0;
	for (size_t i = header; i < size; i++) {
		if (zeros >= 2 && nal[i] == 0x03) {
			zeros = 0;
			continue;
		}
		zeros = nal[i] == 0 ? zeros + 1 : 0;
		rbsp[n++] = nal[i];
	}
	int found = scan_sei_rbsp(rbsp, n, out);
	free(rbsp);
	return found;
}

int stereo_sei_find_packing(const uint8_t *data, size_t size, enum stereo_sei_codec codec, struct stereo_sei_packing *out)
{
	if (!data || !out || (codec != STEREO_SEI_H264 && codec != STEREO_SEI_HEVC))
		return -1;
	size_t i = 0, start = (size_t)-1;
	while (i + 2 < size) {
		if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
			if (start != (size_t)-1) {
				size_t end = i;
				while (end > start && data[end - 1] == 0)
					end--;
				if (scan_nal(data + start, end - start, codec, out))
					return 1;
			}
			i += 3;
			start = i;
			continue;
		}
		i++;
	}
	if (start != (size_t)-1 && start < size)
		return scan_nal(data + start, size - start, codec, out);
	return 0;
}
