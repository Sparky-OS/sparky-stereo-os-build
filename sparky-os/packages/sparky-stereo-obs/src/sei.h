/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
#ifndef SPARKY_STEREO_OBS_SEI_H
#define SPARKY_STEREO_OBS_SEI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum stereo_sei_codec {
	STEREO_SEI_H264 = 0,
	STEREO_SEI_HEVC = 1,
};

/* The first fields of a frame packing arrangement SEI message, payloadType 45: H.264 V16 D.1.26 (semantics D.2.26,
 * Table D-9 for the type, Table D-10 for the eye order) and H.265 V11 D.2.16 (D.3.16, Tables D.8 and D.9). */
struct stereo_sei_packing {
	int cancel;         /* frame_packing_arrangement_cancel_flag */
	int type;           /* frame_packing_arrangement_type, 3 side by side, 4 top and bottom, 5 temporal */
	int quincunx;       /* quincunx_sampling_flag */
	int interpretation; /* content_interpretation_type, 1 frame 0 is the left view, 2 the right */
};

/* Reads the first frame packing arrangement message of an Annex B access unit (H.264 SEI NAL units of type 6, H.265
 * prefix SEI NAL units of type 39), removing emulation prevention bytes. Returns 1 when one was read into out, 0 when the
 * access unit carries none, -1 for a bad argument. */
int stereo_sei_find_packing(const uint8_t *data, size_t size, enum stereo_sei_codec codec, struct stereo_sei_packing *out);

#ifdef __cplusplus
}
#endif

#endif
