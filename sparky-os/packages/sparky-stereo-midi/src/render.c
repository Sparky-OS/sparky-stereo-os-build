/* SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
 * SPDX-License-Identifier: GPL-3.0-or-later
 * FluidSynth's MIDI input stays available; its PipeWire audio stream exists only
 * while voices or an audible effects tail need it. No sound device is opened here.
 */
#include <fluidsynth.h>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <pipewire/thread-loop.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <math.h>
#define CAPACITY 4096
#define RATE 96000
struct event { int type, channel, a, b; uint64_t when; };
struct state {
    fluid_synth_t *synth;
    fluid_midi_event_t *dispatch_event;
    pthread_mutex_t mutex;
    pthread_cond_t changed;
    struct event events[CAPACITY];
    unsigned read, write;
    uint64_t origin;
    long double elapsed;
    unsigned rate;
    struct pw_stream *stream;
    float samples[2][8192];
    int failed;
    unsigned silent;
    int overflow;
};
static volatile sig_atomic_t stopping;
static void stop(int sig) { (void)sig; stopping = 1; }
static uint64_t now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}
static int incoming(void *opaque, fluid_midi_event_t *event) {
    struct state *s = opaque;
    int type = fluid_midi_event_get_type(event);
    pthread_mutex_lock(&s->mutex);
    /* SysEx and system events change the synth's state without advancing its sample clock.
     * The library owns their variable-length data, so consume them within its callback. */
    if (type >= 0xf0 || (s->read == s->write && !s->origin && type != 0x90)) {
        fluid_synth_handle_midi_event(s->synth, event);
    } else if (s->write - s->read == CAPACITY) {
        s->overflow = 1;
    } else {
        s->events[s->write++ % CAPACITY] = (struct event){
            type, fluid_midi_event_get_channel(event), fluid_midi_event_get_key(event),
            fluid_midi_event_get_velocity(event), now() };
        s->silent = 0;
    }
    pthread_cond_signal(&s->changed);
    pthread_mutex_unlock(&s->mutex);
    return FLUID_OK;
}
static void dispatch(struct state *s, struct event *e) {
    fluid_midi_event_t *event = s->dispatch_event;
    fluid_midi_event_set_type(event, e->type);
    fluid_midi_event_set_channel(event, e->channel);
    fluid_midi_event_set_key(event, e->a);
    fluid_midi_event_set_velocity(event, e->b);
    fluid_synth_handle_midi_event(s->synth, event);
}
static int render(void *opaque, int length, int nfx, float **fx, int nout, float **out) {
    struct state *s = opaque;
    int offset = 0;
    (void)nfx; (void)fx;
    pthread_mutex_lock(&s->mutex);
    if (!s->origin && s->read != s->write) s->origin = s->events[s->read % CAPACITY].when;
    while (offset < length) {
        int count = length - offset;
        if (s->read != s->write) {
            struct event *e = &s->events[s->read % CAPACITY];
            long double until = (long double)(e->when - s->origin) - s->elapsed;
            uint64_t due = until > 0 ? until * s->rate / 1000000000 : 0;
            if (due == 0) { dispatch(s, e); s->read++; continue; }
            if (due < (uint64_t)count) count = due;
        }
        float *channels[2] = { out[0] + offset, out[1] + offset };
        for (int ch = 0; ch < nout; ch++) memset(channels[ch], 0, count * sizeof(float));
        if (fluid_synth_process(s->synth, count, nout, channels, nout, channels) != FLUID_OK)
            s->failed = 1;
        s->elapsed += (long double)count * 1000000000 / s->rate; offset += count;
    }
    float peak = 0;
    for (int ch = 0; ch < nout; ch++) for (int i = 0; i < length; i++)
        if (fabsf(out[ch][i]) > peak) peak = fabsf(out[ch][i]);
    /* Below half a signed 24-bit step, no voices, no queued events, for half a second.
     * Effects are actually rendered until this condition holds, not cut off by a note timer. */
    if (peak < 0x1p-24f && !fluid_synth_get_active_voice_count(s->synth) && s->read == s->write)
        s->silent += length;
    else s->silent = 0;
    if (s->silent >= s->rate / 2) pthread_cond_signal(&s->changed);
    pthread_mutex_unlock(&s->mutex);
    return FLUID_OK;
}
/* PipeWire transport follows audio-src.c, Copyright 2020 Wim Taymans (MIT).
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
static void process(void *opaque) {
    struct state *s = opaque;
    struct pw_buffer *buffer = pw_stream_dequeue_buffer(s->stream);
    if (!buffer) return;
    struct spa_data *data = &buffer->buffer->datas[0];
    float *dest = data->data;
    if (!dest) { pw_stream_queue_buffer(s->stream, buffer); return; }
    unsigned length = data->maxsize / (2 * sizeof(float));
    if (buffer->requested && buffer->requested < length) length = buffer->requested;
    if (length > 8192) length = 8192;
    float *out[2] = { s->samples[0], s->samples[1] };
    render(s, length, 0, NULL, 2, out);
    for (unsigned i = 0; i < length; i++) { dest[2*i] = out[0][i]; dest[2*i+1] = out[1][i]; }
    data->chunk->offset = 0; data->chunk->stride = 2 * sizeof(float);
    data->chunk->size = length * data->chunk->stride;
    buffer->size = length;
    pw_stream_queue_buffer(s->stream, buffer);
}
static void state_changed(void *opaque, enum pw_stream_state old,
                          enum pw_stream_state current, const char *error) {
    struct state *s = opaque;
    (void)old; (void)error;
    if (current == PW_STREAM_STATE_ERROR) {
        pthread_mutex_lock(&s->mutex); s->failed = 1;
        pthread_cond_signal(&s->changed); pthread_mutex_unlock(&s->mutex);
    }
}
static const struct pw_stream_events events = {
    PW_VERSION_STREAM_EVENTS, .process = process, .state_changed = state_changed
};
static struct pw_stream *open_audio(struct state *s, struct pw_thread_loop *loop) {
    unsigned char storage[1024];
    struct spa_pod_builder builder = SPA_POD_BUILDER_INIT(storage, sizeof(storage));
    const struct spa_pod *params[1];
    pw_thread_loop_lock(loop);
    s->stream = pw_stream_new_simple(pw_thread_loop_get_loop(loop), "General MIDI",
        pw_properties_new(PW_KEY_NODE_NAME, "sparky-midi-audio",
            PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Playback",
            PW_KEY_MEDIA_ROLE, "Music", PW_KEY_NODE_RATE, "0", NULL), &events, s);
    if (s->stream) {
        params[0] = spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat,
            &SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_F32, .channels = 2,
                .rate = s->rate, .position = { SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR }));
        if (pw_stream_connect(s->stream, PW_DIRECTION_OUTPUT, PW_ID_ANY,
            PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS,
            params, 1) < 0) { pw_stream_destroy(s->stream); s->stream = NULL; }
    }
    pw_thread_loop_unlock(loop);
    return s->stream;
}
static void close_audio(struct pw_stream *audio, struct pw_thread_loop *loop) {
    pw_thread_loop_lock(loop); pw_stream_destroy(audio); pw_thread_loop_unlock(loop);
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--version")) { puts("sparky-stereo-midi 0.1.0"); return 0; }
    if (argc < 2 || argc > 4) return 2;
    pw_init(NULL, NULL);
    struct state s = { .mutex = PTHREAD_MUTEX_INITIALIZER, .changed = PTHREAD_COND_INITIALIZER, .rate = RATE };
    signal(SIGTERM, stop); signal(SIGINT, stop);
    fluid_settings_t *settings = new_fluid_settings();
    fluid_settings_setstr(settings, "audio.driver", "pipewire");
    fluid_settings_setstr(settings, "audio.pipewire.id", "sparky-midi-audio");
    double low, high;
    if (fluid_settings_getnum_range(settings, "synth.sample-rate", &low, &high) != FLUID_OK) return 3;
    s.rate = (unsigned)high;
    fluid_settings_setnum(settings, "synth.sample-rate", high);
    fluid_settings_setint(settings, "audio.period-size", 128);
    fluid_settings_setint(settings, "audio.periods", 2);
    fluid_settings_setstr(settings, "midi.driver", argc > 2 ? argv[2] : "alsa_seq");
    fluid_settings_setstr(settings, "midi.alsa_seq.id", "Sparky General MIDI");
    fluid_settings_setstr(settings, "midi.jack.id", "Sparky General MIDI");
    fluid_settings_setint(settings, "midi.autoconnect", argc > 3 && !strcmp(argv[3], "yes"));
    s.synth = new_fluid_synth(settings);
    s.dispatch_event = new_fluid_midi_event();
    if (!s.synth || !s.dispatch_event) return 3;
    fluid_synth_set_interp_method(s.synth, -1, FLUID_INTERP_7THORDER);
    if ( fluid_synth_sfload(s.synth, argv[1], 1) < 0) return 3;
    setenv("PIPEWIRE_PROPS", "{ media.class = Midi/Sink media.type = Midi media.category = Playback node.name = sparky-midi }", 1);
    fluid_midi_driver_t *midi = new_fluid_midi_driver(settings, incoming, &s);
    unsetenv("PIPEWIRE_PROPS");
    if (!midi) { delete_fluid_synth(s.synth); delete_fluid_settings(settings); return 4; }
    puts("READY"); fflush(stdout);
    struct pw_thread_loop *loop = pw_thread_loop_new("midi-audio", NULL);
    if (!loop || pw_thread_loop_start(loop) < 0) return 6;
    struct pw_stream *audio = NULL;
    uint64_t opened = 0;
    while (!stopping) {
        pthread_mutex_lock(&s.mutex);
        int queued = s.write != s.read, idle = s.silent >= s.rate / 2, overflow = s.overflow, failed = s.failed, started = s.origin != 0;
        pthread_mutex_unlock(&s.mutex);
        if (overflow || failed) { stopping = overflow ? 5 : 6; break; }
        if (!audio && queued) {
            audio = open_audio(&s, loop); opened = now();
            if (!audio) { stopping = 6; break; }
        } else if (audio && idle && !queued) {
            close_audio(audio, loop); audio = NULL;
            pthread_mutex_lock(&s.mutex); s.origin = s.silent = 0; s.elapsed = 0; pthread_mutex_unlock(&s.mutex);
        }
        if (audio && queued && !started && now() - opened > 5000000000ULL) { stopping = 6; break; }
        struct timespec until; clock_gettime(CLOCK_REALTIME, &until); until.tv_sec++;
        pthread_mutex_lock(&s.mutex);
        if (!stopping && s.write == s.read && s.silent < s.rate / 2)
            pthread_cond_timedwait(&s.changed, &s.mutex, &until);
        pthread_mutex_unlock(&s.mutex);
    }
    delete_fluid_midi_driver(midi);
    if (audio) close_audio(audio, loop);
    pw_thread_loop_stop(loop); pw_thread_loop_destroy(loop);
    delete_fluid_midi_event(s.dispatch_event);
    delete_fluid_synth(s.synth); delete_fluid_settings(settings);
    pw_deinit();
    return stopping > 1 ? stopping : 0;
}
