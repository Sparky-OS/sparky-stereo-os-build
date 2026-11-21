/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
/* The SEI reader against frame packing messages written bit by bit from the syntax of H.264 V16 D.1.26: both eye
 * orders, the cancel flag, a message after another payload, emulation prevention, H.265's prefix SEI, and units that
 * carry none. */
#include "../src/sei.h"

#include <stdio.h>
#include <string.h>

struct writer {
	uint8_t bytes[64];
	size_t bits;
};

static void put(struct writer *w, unsigned long value, int count)
{
	for (int i = count - 1; i >= 0; i--) {
		if ((value >> i) & 1)
			w->bytes[w->bits / 8] |= (uint8_t)(0x80 >> (w->bits % 8));
		w->bits++;
	}
}

static void put_ue(struct writer *w, unsigned long value)
{
	unsigned long v = value + 1;
	int length = 0;
	while ((v >> length) > 1)
		length++;
	put(w, 0, length);
	put(w, v, length + 1);
}

/* frame_packing_arrangement( ) with the fields this reader and x264 use */
static size_t packing_payload(uint8_t *out, int cancel, int type, int interpretation)
{
	struct writer w;
	memset(&w, 0, sizeof(w));
	put_ue(&w, 0);
	put(&w, (unsigned long)cancel, 1);
	if (!cancel) {
		put(&w, (unsigned long)type, 7);
		put(&w, 0, 1);
		put(&w, (unsigned long)interpretation, 6);
		put(&w, 0, 6);  /* spatial_flipping .. frame1_self_contained */
		put(&w, 0, 16); /* frame0 and frame1 grid positions */
		put(&w, 0, 8);  /* frame_packing_arrangement_reserved_byte */
		put_ue(&w, 1);  /* repetition period */
	}
	put(&w, 0, 1); /* frame_packing_arrangement_extension_flag */
	if (w.bits % 8) {
		put(&w, 1, 1);
		while (w.bits % 8)
			put(&w, 0, 1);
	}
	memcpy(out, w.bytes, w.bits / 8);
	return w.bits / 8;
}

/* start code, NAL header, payloads with emulation prevention, rbsp trailing bits */
static size_t unit(uint8_t *out, const uint8_t *header, size_t header_size, const uint8_t *rbsp, size_t size)
{
	size_t n = 0, zeros = 0;
	out[n++] = 0;
	out[n++] = 0;
	out[n++] = 0;
	out[n++] = 1;
	memcpy(out + n, header, header_size);
	n += header_size;
	for (size_t i = 0; i < size; i++) {
		if (zeros >= 2 && rbsp[i] <= 3) {
			out[n++] = 3;
			zeros = 0;
		}
		zeros = rbsp[i] == 0 ? zeros + 1 : 0;
		out[n++] = rbsp[i];
	}
	out[n++] = 0x80;
	return n;
}

static int failures;

static void expect(const char *name, int got, int want)
{
	if (got != want) {
		printf("FAIL %s: %d, expected %d\n", name, got, want);
		failures++;
	} else {
		printf("ok   %s\n", name);
	}
}

static size_t sei_rbsp(uint8_t *rbsp, int with_other_first, int cancel, int type, int interpretation)
{
	size_t n = 0;
	if (with_other_first) {
		rbsp[n++] = 5; /* user_data_unregistered, 17 bytes of zeros */
		rbsp[n++] = 17;
		memset(rbsp + n, 0, 17);
		n += 17;
	}
	uint8_t payload[32];
	size_t size = packing_payload(payload, cancel, type, interpretation);
	rbsp[n++] = 45;
	rbsp[n++] = (uint8_t)size;
	memcpy(rbsp + n, payload, size);
	return n + size;
}

int main(void)
{
	static const uint8_t h264_sei[] = {0x06};
	static const uint8_t h264_idr[] = {0x65};
	static const uint8_t hevc_prefix_sei[] = {39 << 1, 1};
	uint8_t au[256], rbsp[96], slice[] = {0x88, 0x84, 0x00, 0x00, 0x00, 0x21};
	struct stereo_sei_packing p;
	size_t n;

	n = unit(au, h264_sei, 1, rbsp, sei_rbsp(rbsp, 0, 0, 3, 1));
	n += unit(au + n, h264_idr, 1, slice, sizeof(slice));
	expect("h264 side by side found", stereo_sei_find_packing(au, n, STEREO_SEI_H264, &p), 1);
	expect("h264 side by side type", p.type, 3);
	expect("h264 left eye first", p.interpretation, 1);

	n = unit(au, h264_sei, 1, rbsp, sei_rbsp(rbsp, 1, 0, 4, 2));
	expect("h264 after another payload found", stereo_sei_find_packing(au, n, STEREO_SEI_H264, &p), 1);
	expect("h264 top and bottom type", p.type, 4);
	expect("h264 right eye first", p.interpretation, 2);

	n = unit(au, h264_sei, 1, rbsp, sei_rbsp(rbsp, 0, 1, 0, 0));
	expect("h264 cancel found", stereo_sei_find_packing(au, n, STEREO_SEI_H264, &p), 1);
	expect("h264 cancel flag", p.cancel, 1);

	n = unit(au, hevc_prefix_sei, 2, rbsp, sei_rbsp(rbsp, 0, 0, 5, 1));
	expect("hevc temporal found", stereo_sei_find_packing(au, n, STEREO_SEI_HEVC, &p), 1);
	expect("hevc temporal type", p.type, 5);
	expect("hevc unit read as h264 gives none", stereo_sei_find_packing(au, n, STEREO_SEI_H264, &p), 0);

	n = unit(au, h264_idr, 1, slice, sizeof(slice));
	expect("plain picture carries none", stereo_sei_find_packing(au, n, STEREO_SEI_H264, &p), 0);
	expect("null argument", stereo_sei_find_packing(NULL, 0, STEREO_SEI_H264, &p), -1);

	printf("%d failing\n", failures);
	return failures ? 1 : 0;
}
