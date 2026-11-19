/* SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Adapted from the ORDER 631 fake ALSA device. */
/* A fake ALSA sound device for the audio-defaults rig (ORDER 631): it takes exactly the rates, formats and channel
 * counts it is told to, paces itself at the wall clock like hardware, and writes what it received to a file, so the
 * rate and the format PipeWire opened the "device" with, and the samples it sent, can be read back.
 *
 * ~/.asoundrc / /etc/asound.conf:
 *   pcm_type.as21 { lib "/path/libasound_module_pcm_as21.so" }
 *   pcm.dev96 { type as21; rates "44100 48000 88200 96000"; formats "S16_LE S24_3LE S32_LE"; channels 2; out "/run/sa/dev96.raw" }
 * The negotiated parameters are written to OUT.params when the device is prepared. */
#include <alsa/asoundlib.h>
#include <alsa/pcm_external.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <sys/timerfd.h>
#include <unistd.h>

#define MAXV 16
typedef struct {
	snd_pcm_ioplug_t io;
	unsigned rates[MAXV]; unsigned nrates;
	unsigned formats[MAXV]; unsigned nformats;
	unsigned channels;
	char out[512];
	FILE *fp;
	int tfd;
	struct timespec t0;
	snd_pcm_uframes_t started_at, hw;
	snd_pcm_uframes_t written;
	int running;
} sa_t;

static double now_since(const struct timespec *t0) {
	struct timespec n; clock_gettime(CLOCK_MONOTONIC, &n);
	return (n.tv_sec - t0->tv_sec) + (n.tv_nsec - t0->tv_nsec) / 1e9;
}

static snd_pcm_sframes_t sa_pointer(snd_pcm_ioplug_t *io) {
	sa_t *s = io->private_data;
	if (!s->running) return s->hw % io->buffer_size;
	snd_pcm_uframes_t el = (snd_pcm_uframes_t)(now_since(&s->t0) * io->rate);
	snd_pcm_uframes_t hw = s->started_at + el;
	/* never ahead of what the application wrote: the device cannot play what it has not got */
	snd_pcm_uframes_t wr = s->written;
	if (hw > wr) hw = wr;
	s->hw = hw;
	return hw % io->buffer_size;
}

static snd_pcm_sframes_t sa_transfer(snd_pcm_ioplug_t *io, const snd_pcm_channel_area_t *areas,
				     snd_pcm_uframes_t offset, snd_pcm_uframes_t size) {
	sa_t *s = io->private_data;
	unsigned fb = snd_pcm_format_physical_width(io->format) / 8 * io->channels;
	const char *p = (const char *)areas[0].addr + (areas[0].first + offset * areas[0].step) / 8;
	if (s->fp) { fwrite(p, fb, size, s->fp); fflush(s->fp); }
	s->written += size;
	return size;
}

static int sa_start(snd_pcm_ioplug_t *io) {
	sa_t *s = io->private_data;
	clock_gettime(CLOCK_MONOTONIC, &s->t0);
	s->started_at = s->hw;
	s->running = 1;
	double per = (double)io->period_size / io->rate;
	struct itimerspec it = { .it_interval = { (time_t)per, (long)((per - (time_t)per) * 1e9) } };
	it.it_value = it.it_interval;
	timerfd_settime(s->tfd, 0, &it, NULL);
	return 0;
}
static int sa_stop(snd_pcm_ioplug_t *io) {
	sa_t *s = io->private_data;
	sa_pointer(io);
	s->running = 0;
	struct itimerspec it; memset(&it, 0, sizeof it);
	timerfd_settime(s->tfd, 0, &it, NULL);
	return 0;
}
static int sa_prepare(snd_pcm_ioplug_t *io) {
	sa_t *s = io->private_data;
	s->hw = 0; s->written = 0; s->running = 0;
	char path[600]; snprintf(path, sizeof path, "%s.params", s->out);
	FILE *f = fopen(path, "w");
	if (f) {
		fprintf(f, "{\"rate\": %u, \"format\": \"%s\", \"channels\": %u, \"period_size\": %lu, \"buffer_size\": %lu}\n",
			io->rate, snd_pcm_format_name(io->format), io->channels,
			(unsigned long)io->period_size, (unsigned long)io->buffer_size);
		fclose(f);
	}
	if (s->fp) fclose(s->fp);
	snprintf(path, sizeof path, "%s.%s", s->out, snd_pcm_format_name(io->format));
	s->fp = fopen(path, "ab");
	return 0;
}
static int sa_poll_revents(snd_pcm_ioplug_t *io, struct pollfd *pfd, unsigned nfds, unsigned short *revents) {
	sa_t *s = io->private_data; uint64_t n;
	if (read(s->tfd, &n, sizeof n) < 0) {}
	*revents = POLLOUT;
	(void)pfd; (void)nfds;
	return 0;
}
static int sa_close(snd_pcm_ioplug_t *io) {
	sa_t *s = io->private_data;
	if (s->fp) fclose(s->fp);
	close(s->tfd); free(s);
	return 0;
}
static int sa_hw_params(snd_pcm_ioplug_t *io, snd_pcm_hw_params_t *p) {
    (void)p;
    if (getenv("AS21_REJECT") && io->format == SND_PCM_FORMAT_S16_LE) return -EIO;
    return 0;
}
static const snd_pcm_ioplug_callback_t cb = {
	.start = sa_start, .stop = sa_stop, .pointer = sa_pointer, .transfer = sa_transfer,
	.prepare = sa_prepare, .close = sa_close, .hw_params = sa_hw_params, .poll_revents = sa_poll_revents,
};

static unsigned parse_list(const char *str, unsigned *out, int fmt) {
	char *c = strdup(str), *sv = NULL, *t; unsigned n = 0;
	for (t = strtok_r(c, " ,", &sv); t && n < MAXV; t = strtok_r(NULL, " ,", &sv))
		out[n++] = fmt ? (unsigned)snd_pcm_format_value(t) : (unsigned)atoi(t);
	free(c); return n;
}

SND_PCM_PLUGIN_DEFINE_FUNC(as21) {
	snd_config_iterator_t i, next; sa_t *s; int err;
	const char *rates = "48000", *formats = "S16_LE", *out = "/dev/null"; long channels = 2;
	snd_config_for_each(i, next, conf) {
		snd_config_t *n = snd_config_iterator_entry(i); const char *id;
		if (snd_config_get_id(n, &id) < 0) continue;
		if (!strcmp(id, "comment") || !strcmp(id, "type") || !strcmp(id, "hint")) continue;
		if (!strcmp(id, "rates")) snd_config_get_string(n, &rates);
		else if (!strcmp(id, "formats")) snd_config_get_string(n, &formats);
		else if (!strcmp(id, "channels")) snd_config_get_integer(n, &channels);
		else if (!strcmp(id, "out")) snd_config_get_string(n, &out);
	}
	if (stream != SND_PCM_STREAM_PLAYBACK) return -EINVAL;
	s = calloc(1, sizeof *s); if (!s) return -ENOMEM;
	s->nrates = parse_list(rates, s->rates, 0); s->nformats = parse_list(formats, s->formats, 1);
	s->channels = channels; snprintf(s->out, sizeof s->out, "%s", out);
	s->tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
	s->io.version = SND_PCM_IOPLUG_VERSION; s->io.name = "as21 fake device"; s->io.callback = &cb;
	s->io.private_data = s; s->io.poll_fd = s->tfd; s->io.poll_events = POLLIN; s->io.mmap_rw = 0;
	if ((err = snd_pcm_ioplug_create(&s->io, name, stream, mode)) < 0) { free(s); return err; }
	snd_pcm_ioplug_set_param_list(&s->io, SND_PCM_IOPLUG_HW_RATE, s->nrates, s->rates);
	snd_pcm_ioplug_set_param_list(&s->io, SND_PCM_IOPLUG_HW_FORMAT, s->nformats, s->formats);
	snd_pcm_ioplug_set_param_minmax(&s->io, SND_PCM_IOPLUG_HW_CHANNELS, s->channels, s->channels);
	{ unsigned acc[1] = { SND_PCM_ACCESS_RW_INTERLEAVED }; snd_pcm_ioplug_set_param_list(&s->io, SND_PCM_IOPLUG_HW_ACCESS, 1, acc); }
	snd_pcm_ioplug_set_param_minmax(&s->io, SND_PCM_IOPLUG_HW_PERIODS, 2, 16);
	snd_pcm_ioplug_set_param_minmax(&s->io, SND_PCM_IOPLUG_HW_PERIOD_BYTES, 128, 64 * 1024);
	snd_pcm_ioplug_set_param_minmax(&s->io, SND_PCM_IOPLUG_HW_BUFFER_BYTES, 1024, 1024 * 1024);
	*pcmp = s->io.pcm;
	return 0;
}
SND_PCM_PLUGIN_SYMBOL(as21);
