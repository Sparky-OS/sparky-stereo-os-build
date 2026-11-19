/* SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
 * SPDX-License-Identifier: GPL-3.0-or-later
 * FluidSynth's MIDI input stays available; its native PipeWire audio driver exists only
 * while voices or an audible effects tail need it. No sound device is opened here.
 */
#include <fluidsynth.h>
#include <pipewire/pipewire.h>
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
#define RATE 48000
struct event { int type, channel, a, b; uint64_t when; };
struct state {
    fluid_synth_t *synth;
    fluid_midi_event_t *dispatch_event;
    pthread_mutex_t mutex;
    pthread_cond_t changed;
    struct event events[CAPACITY];
    unsigned read, write;
    uint64_t origin, frame;
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
            uint64_t due = (e->when - s->origin) * RATE / 1000000000;
            if (due <= s->frame) { dispatch(s, e); s->read++; continue; }
            if (due - s->frame < (uint64_t)count) count = due - s->frame;
        }
        float *channels[2] = { out[0] + offset, out[1] + offset };
        fluid_synth_process(s->synth, count, 0, NULL, nout, channels);
        s->frame += count; offset += count;
    }
    float peak = 0;
    for (int ch = 0; ch < nout; ch++) for (int i = 0; i < length; i++)
        if (fabsf(out[ch][i]) > peak) peak = fabsf(out[ch][i]);
    /* Below half a signed 24-bit step, no voices, no queued events, for half a second.
     * Effects are actually rendered until this condition holds, not cut off by a note timer. */
    if (peak < 0x1p-24f && !fluid_synth_get_active_voice_count(s->synth) && s->read == s->write)
        s->silent += length;
    else s->silent = 0;
    if (s->silent >= RATE / 2) pthread_cond_signal(&s->changed);
    pthread_mutex_unlock(&s->mutex);
    return FLUID_OK;
}
int main(int argc, char **argv) {
    if (argc < 2 || argc > 4) return 2;
    pw_init(NULL, NULL);
    struct state s = { .mutex = PTHREAD_MUTEX_INITIALIZER, .changed = PTHREAD_COND_INITIALIZER };
    signal(SIGTERM, stop); signal(SIGINT, stop);
    fluid_settings_t *settings = new_fluid_settings();
    fluid_settings_setstr(settings, "audio.driver", "pipewire");
    fluid_settings_setstr(settings, "audio.pipewire.id", "sparky-midi-audio");
    fluid_settings_setnum(settings, "synth.sample-rate", RATE);
    fluid_settings_setint(settings, "audio.period-size", 128);
    fluid_settings_setint(settings, "audio.periods", 2);
    fluid_settings_setstr(settings, "midi.driver", argc > 2 ? argv[2] : "alsa_seq");
    fluid_settings_setstr(settings, "midi.alsa_seq.id", "Sparky General MIDI");
    fluid_settings_setstr(settings, "midi.jack.id", "Sparky General MIDI");
    fluid_settings_setint(settings, "midi.autoconnect", argc > 3 && !strcmp(argv[3], "yes"));
    s.synth = new_fluid_synth(settings);
    s.dispatch_event = new_fluid_midi_event();
    if (!s.synth || fluid_synth_sfload(s.synth, argv[1], 1) < 0) return 3;
    setenv("PIPEWIRE_PROPS", "{ media.class = Midi/Sink media.type = Midi media.category = Playback node.name = sparky-midi }", 1);
    fluid_midi_driver_t *midi = new_fluid_midi_driver(settings, incoming, &s);
    unsetenv("PIPEWIRE_PROPS");
    if (!midi) { delete_fluid_synth(s.synth); delete_fluid_settings(settings); return 4; }
    fluid_audio_driver_t *audio = NULL;
    while (!stopping) {
        pthread_mutex_lock(&s.mutex);
        int queued = s.write != s.read, idle = s.silent >= RATE / 2, overflow = s.overflow;
        pthread_mutex_unlock(&s.mutex);
        if (overflow) { stopping = 5; break; }
        if (!audio && queued) {
            audio = new_fluid_audio_driver2(settings, render, &s);
            if (!audio) { stopping = 6; break; }
        } else if (audio && idle && !queued) {
            delete_fluid_audio_driver(audio); audio = NULL;
            pthread_mutex_lock(&s.mutex); s.origin = s.frame = s.silent = 0; pthread_mutex_unlock(&s.mutex);
        }
        struct timespec until; clock_gettime(CLOCK_REALTIME, &until); until.tv_sec++;
        pthread_mutex_lock(&s.mutex);
        if (!stopping && s.write == s.read && s.silent < RATE / 2)
            pthread_cond_timedwait(&s.changed, &s.mutex, &until);
        pthread_mutex_unlock(&s.mutex);
    }
    delete_fluid_midi_driver(midi);
    if (audio) delete_fluid_audio_driver(audio);
    delete_fluid_midi_event(s.dispatch_event);
    delete_fluid_synth(s.synth); delete_fluid_settings(settings);
    pw_deinit();
    return stopping > 1 ? stopping : 0;
}
