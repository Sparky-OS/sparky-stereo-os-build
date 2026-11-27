/* SPDX-FileCopyrightText: 2026 Daniel Campos Ramos */
/* SPDX-License-Identifier: MIT */
/*
 * Checks the edition's PipeWire AAC codec plugin (pipewire-bluez5-codec-aac) against the PipeWire it is installed with,
 * without a Bluetooth device: PipeWire's own SPA loader loads the plugin as the Bluetooth monitor's codec loader does
 * (spa/plugins/bluez5/codec-loader.c), and the codec's own encode and decode functions carry a test tone.
 *
 * Build against the matching PipeWire source's private codec header, with the SPA_AUDIO_MAX_CHANNELS of its meson.build
 * (128 in 1.6; the plugin clears a struct spa_audio_info of that size, so a smaller one overruns the caller's stack):
 *   cc -O1 -g -DSPA_AUDIO_MAX_CHANNELS=128u codec-check.c -I PIPEWIRE_SOURCE/spa/plugins/bluez5 \
 *      $(pkg-config --cflags --libs libpipewire-0.3) -lm
 * Modes (exit 0 when the mode's own check passes, 1 when it fails, 2 on a usage or set-up error):
 *   monitor  load PipeWire's Bluetooth monitor (api.bluez5.enum.dbus); it loads every codec plugin before it needs a
 *            system bus, so run with PIPEWIRE_DEBUG=spa.bluez5.codecs:4 and read "loaded media codec aac" on stderr
 *   codec    the plugin's interface version against this header's, then 1.5 s of a 1 kHz tone at 48 kHz encoded and
 *            decoded through the codec; passes when both channels are the tone (Goertzel share >= 0.97, level within 5 %)
 *   bounds   one AAC frame decoded into a buffer smaller than the frame (3000 bytes, a frame is 4096) followed by a
 *            guard area; prints how many guard bytes changed. Upstream commit 35b4d051d48e (bluez5: avoid heap overflow
 *            in AAC decoder, in 1.6.11) makes the decoder refuse; before it the decoder writes past the buffer.
 *            Passes when the decoder refused and no guard byte changed.
 * SPA_PLUGIN_DIR selects the plugin tree, so a predecessor's plugin can be checked beside the installed one.
 */
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <pipewire/pipewire.h>
#include <spa/param/audio/format.h>
#include <spa/utils/dict.h>
#include <spa/utils/result.h>
#include <spa/utils/string.h>

#include "media-codecs.h"

#define RATE 48000
#define TONE 1000.0
#define AMPLITUDE 0.5
#define MTU 1024
#define SECONDS 1.5
#define PCM_CAP 16384
#define SMALL_DST 3000
#define GUARD 4096
#define GUARD_BYTE 0xa5

static struct spa_handle *load(struct pw_context *context, const char *factory, const char *library)
{
	struct spa_dict_item items[] = { SPA_DICT_ITEM_INIT(SPA_KEY_LIBRARY_NAME, library) };
	struct spa_dict info = SPA_DICT_INIT_ARRAY(items);
	return pw_context_load_spa_handle(context, factory, &info);
}

static const struct media_codec *find_aac(struct spa_handle *handle)
{
	void *iface = NULL;
	const struct spa_bluez5_codec_a2dp *codecs;
	int res;

	if ((res = spa_handle_get_interface(handle, SPA_TYPE_INTERFACE_Bluez5CodecMedia, &iface)) < 0) {
		printf("interface: none (%s)\n", spa_strerror(res));
		return NULL;
	}
	codecs = iface;
	printf("interface: %s version %u, this check's header %d\n", SPA_TYPE_INTERFACE_Bluez5CodecMedia,
	       codecs->iface.version, SPA_VERSION_BLUEZ5_CODEC_MEDIA);
	if (codecs->iface.version != SPA_VERSION_BLUEZ5_CODEC_MEDIA) {
		printf("interface: incompatible, as codec-loader.c would refuse it\n");
		return NULL;
	}
	for (size_t i = 0; codecs->codecs[i]; i++)
		printf("codec: %s (%s) endpoint %s\n", codecs->codecs[i]->name, codecs->codecs[i]->description,
		       codecs->codecs[i]->endpoint_name ? codecs->codecs[i]->endpoint_name : codecs->codecs[i]->name);
	for (size_t i = 0; codecs->codecs[i]; i++)
		if (spa_streq(codecs->codecs[i]->name, "aac"))
			return codecs->codecs[i];
	printf("codec: no codec named aac\n");
	return NULL;
}

static void *open_codec(const struct media_codec *codec, struct spa_audio_info *info, void **props)
{
	uint8_t caps[A2DP_MAX_CAPS_SIZE], config[A2DP_MAX_CAPS_SIZE];
	struct media_codec_audio_info want = { .rate = RATE, .channels = 2 };
	void *config_data = NULL;
	int caps_size, config_size, res;

	if ((caps_size = codec->fill_caps(codec, 0, NULL, caps)) < 0) {
		printf("fill_caps: %s\n", spa_strerror(caps_size));
		return NULL;
	}
	if ((config_size = codec->select_config(codec, 0, caps, caps_size, &want, NULL, config, &config_data)) < 0) {
		printf("select_config: %s\n", spa_strerror(config_size));
		return NULL;
	}
	spa_zero(*info);
	if ((res = codec->validate_config(codec, 0, config, config_size, info)) < 0) {
		printf("validate_config: %s\n", spa_strerror(res));
		return NULL;
	}
	*props = codec->init_props ? codec->init_props(codec, 0, NULL) : NULL;
	return codec->init(codec, 0, config, config_size, info, *props, MTU);
}

struct stream {
	uint8_t *data;
	size_t size, *packet_sizes;
	int packets;
};

static int encode_tone(const struct media_codec *codec, void *encoder, struct stream *out)
{
	int block = codec->get_block_size(encoder);
	size_t frames = (size_t)(RATE * SECONDS), at = 0;
	int16_t *pcm = calloc(frames * 2, sizeof(int16_t));
	uint8_t packet[4096];
	uint16_t seq = 0;
	uint32_t timestamp = 0;

	if (pcm == NULL || block <= 0)
		return -1;
	for (size_t i = 0; i < frames; i++)
		pcm[2 * i] = pcm[2 * i + 1] = (int16_t)lrint(AMPLITUDE * 32767.0 * sin(2.0 * M_PI * TONE * i / RATE));
	out->data = malloc(frames * 4);
	out->packet_sizes = calloc(frames, sizeof(size_t));
	while (at + (size_t)block <= frames * 4) {
		size_t written = 0;
		int flush = 0, header, used;

		header = codec->start_encode(encoder, packet, sizeof(packet), seq, timestamp);
		used = codec->encode(encoder, (uint8_t *)pcm + at, block, packet + header, sizeof(packet) - header,
				     &written, &flush);
		if (header < 0 || used < 0) {
			printf("encode: %s\n", spa_strerror(header < 0 ? header : used));
			return -1;
		}
		at += used;
		timestamp += used / 4;
		if (written > 0) {
			memcpy(out->data + out->size, packet, header + written);
			out->packet_sizes[out->packets++] = header + written;
			out->size += header + written;
			seq++;
		}
		if (used == 0 && written == 0)
			break;
	}
	free(pcm);
	printf("encode: %zu bytes of PCM in, %d packets, %zu bytes out\n", at, out->packets, out->size);
	return out->packets > 0 ? 0 : -1;
}

/* the share of a channel's energy that sits at TONE, and its RMS level */
static void measure(const int16_t *pcm, size_t first, size_t count, int channel, double *share, double *rms)
{
	double coeff = 2.0 * cos(2.0 * M_PI * TONE / RATE), s1 = 0, s2 = 0, energy = 0;

	for (size_t i = first; i < first + count; i++) {
		double x = pcm[2 * i + channel] / 32768.0, s0 = x + coeff * s1 - s2;
		s2 = s1;
		s1 = s0;
		energy += x * x;
	}
	*share = energy > 0 ? (s1 * s1 + s2 * s2 - coeff * s1 * s2) / (count * energy / 2.0) : 0;
	*rms = sqrt(energy / count);
}

static int mode_codec(const struct media_codec *codec)
{
	struct spa_audio_info info;
	void *eprops = NULL, *dprops = NULL, *encoder = open_codec(codec, &info, &eprops), *decoder;
	struct stream stream = { 0 };
	uint8_t *pcm;
	size_t pcm_size = 0, offset = 0;
	int failed = 0;

	if (encoder == NULL) {
		printf("init: encoder refused\n");
		return 1;
	}
	printf("format: rate %u, channels %u, block %d bytes\n", info.info.raw.rate, info.info.raw.channels,
	       codec->get_block_size(encoder));
	if (encode_tone(codec, encoder, &stream) < 0)
		return 1;
	decoder = open_codec(codec, &info, &dprops);
	pcm = malloc((size_t)(RATE * SECONDS) * 4 + PCM_CAP);
	if (decoder == NULL || pcm == NULL) {
		printf("init: decoder refused\n");
		return 1;
	}
	for (int p = 0; p < stream.packets; p++) {
		const uint8_t *packet = stream.data + offset;
		size_t size = stream.packet_sizes[p], out = 0;
		int header = codec->start_decode(decoder, packet, size, NULL, NULL), used;

		offset += size;
		if (header < 0) {
			printf("decode: packet %d header %s\n", p, spa_strerror(header));
			return 1;
		}
		used = codec->decode(decoder, packet + header, size - header, pcm + pcm_size, PCM_CAP, &out);
		if (used < 0) {
			printf("decode: packet %d %s\n", p, spa_strerror(used));
			return 1;
		}
		pcm_size += out;
	}
	printf("decode: %zu bytes of PCM out (%zu frames)\n", pcm_size, pcm_size / 4);
	/* skip the codec's delay and the encoder's start, then measure 800 whole periods of the tone */
	size_t first = 4096, count = 48 * 800;
	if (pcm_size / 4 < first + count) {
		printf("decode: too little audio to measure\n");
		return 1;
	}
	for (int channel = 0; channel < 2; channel++) {
		double share, rms, expected = AMPLITUDE / sqrt(2.0);
		measure((const int16_t *)pcm, first, count, channel, &share, &rms);
		int ok = share >= 0.97 && fabs(rms - expected) <= 0.05 * expected;
		printf("tone: channel %d share at %.0f Hz %.4f, RMS %.4f (expected %.4f) %s\n", channel, TONE, share, rms,
		       expected, ok ? "ok" : "WRONG");
		failed |= !ok;
	}
	codec->deinit(encoder);
	codec->deinit(decoder);
	if (codec->clear_props) {
		codec->clear_props(eprops);
		codec->clear_props(dprops);
	}
	free(pcm);
	printf("codec: %s\n", failed ? "FAIL" : "PASS");
	return failed;
}

static int mode_bounds(const struct media_codec *codec)
{
	struct spa_audio_info info;
	void *eprops = NULL, *dprops = NULL, *encoder = open_codec(codec, &info, &eprops), *decoder;
	struct stream stream = { 0 };
	uint8_t *pcm = malloc(PCM_CAP), *small = malloc(SMALL_DST + GUARD);
	size_t offset = 0, out = 0, changed = 0;
	int last, header, res;

	if (encoder == NULL || encode_tone(codec, encoder, &stream) < 0 || pcm == NULL || small == NULL)
		return 2;
	decoder = open_codec(codec, &info, &dprops);
	if (decoder == NULL || stream.packets < 6)
		return 2;
	last = stream.packets - 1;
	for (int p = 0; p < last; p++) {
		header = codec->start_decode(decoder, stream.data + offset, stream.packet_sizes[p], NULL, NULL);
		codec->decode(decoder, stream.data + offset + header, stream.packet_sizes[p] - header, pcm, PCM_CAP, &out);
		offset += stream.packet_sizes[p];
	}
	memset(small, GUARD_BYTE, SMALL_DST + GUARD);
	header = codec->start_decode(decoder, stream.data + offset, stream.packet_sizes[last], NULL, NULL);
	out = 0;
	res = codec->decode(decoder, stream.data + offset + header, stream.packet_sizes[last] - header, small, SMALL_DST, &out);
	for (size_t i = SMALL_DST; i < SMALL_DST + GUARD; i++)
		changed += small[i] != GUARD_BYTE;
	printf("bounds: buffer %d bytes, frame %d bytes; decode returned %d (%s), reported %zu bytes; %zu guard bytes changed\n",
	       SMALL_DST, codec->get_block_size(decoder), res, res < 0 ? spa_strerror(res) : "accepted", out, changed);
	printf("bounds: %s\n", res < 0 && changed == 0 ? "PASS (refused, nothing written past the buffer)" :
	       "FAIL (the decoder wrote past the buffer it was given)");
	codec->deinit(encoder);
	codec->deinit(decoder);
	if (codec->clear_props) {
		codec->clear_props(eprops);
		codec->clear_props(dprops);
	}
	free(pcm);
	free(small);
	return !(res < 0 && changed == 0);
}

int main(int argc, char *argv[])
{
	struct pw_main_loop *loop;
	struct pw_context *context;
	struct spa_handle *handle;
	const struct media_codec *codec;
	int monitor, res = 2;

	if (argc != 2 || (strcmp(argv[1], "monitor") && strcmp(argv[1], "codec") && strcmp(argv[1], "bounds"))) {
		fprintf(stderr, "usage: %s monitor|codec|bounds\n", argv[0]);
		return 2;
	}
	monitor = !strcmp(argv[1], "monitor");
	pw_init(&argc, &argv);
	setvbuf(stdout, NULL, _IOLBF, 0);
	loop = pw_main_loop_new(NULL);
	context = pw_context_new(pw_main_loop_get_loop(loop),
				 pw_properties_new("support.dbus", monitor ? "true" : "false", NULL), 0);
	if (context == NULL) {
		printf("context: %s\n", strerror(errno));
		return 2;
	}
	printf("plugins: %s\n", getenv("SPA_PLUGIN_DIR") ? getenv("SPA_PLUGIN_DIR") : "(PipeWire's default)");
	if (monitor) {
		/* without a system bus the monitor stops after it has loaded the codecs; its log lines are the result */
		handle = load(context, "api.bluez5.enum.dbus", "bluez5/libspa-bluez5");
		printf("monitor: %s\n", handle ? "started" : "stopped after loading its codecs (no system bus here)");
		res = 0;
	} else {
		handle = load(context, MEDIA_CODEC_FACTORY_NAME("aac"), "bluez5/libspa-codec-bluez5-aac");
		if (handle == NULL) {
			printf("load: %s refused by PipeWire's loader (%s)\n", MEDIA_CODEC_FACTORY_NAME("aac"), strerror(errno));
			res = 1;
		} else if ((codec = find_aac(handle)) == NULL) {
			res = 1;
		} else {
			res = !strcmp(argv[1], "codec") ? mode_codec(codec) : mode_bounds(codec);
		}
		if (handle)
			pw_unload_spa_handle(handle);
	}
	pw_context_destroy(context);
	pw_main_loop_destroy(loop);
	pw_deinit();
	return res;
}
