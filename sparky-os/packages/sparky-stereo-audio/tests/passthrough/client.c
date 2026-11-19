/* SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
 * SPDX-License-Identifier: GPL-3.0-or-later
 * A player fixture offering AC3 and decoded PCM to the real Pulse server.
 * The chosen format decides which independently prepared file is sent. */
#include <pulse/pulseaudio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static pa_mainloop *loop;
static pa_context *context;
static pa_stream *stream;
static FILE *input;
static int done, failure, announced, want_encoded;
static const char *encoded, *decoded, *sink;

static void drained(pa_stream *s, int success, void *arg) { done=1; if (!success) failure=1; }
static void request(pa_stream *s, size_t bytes, void *arg) {
    if (done || !input) return;
    unsigned char *data=malloc(bytes);
    size_t count=fread(data,1,bytes,input);
    if (count && pa_stream_write(s,data,count,free,0,PA_SEEK_RELATIVE)<0) { free(data); failure=done=1; return; }
    if (!count) free(data);
    if (feof(input)) {
        fclose(input); input=NULL;
        pa_operation *op=pa_stream_drain(s,drained,NULL);
        if (op) pa_operation_unref(op); else failure=done=1;
    }
}
static void stream_state(pa_stream *s, void *arg) {
    pa_stream_state_t state=pa_stream_get_state(s);
    if (state==PA_STREAM_FAILED || state==PA_STREAM_TERMINATED) { if (!done) failure=1; done=1; return; }
    if (state!=PA_STREAM_READY || announced) return;
    announced=1;
    const pa_format_info *f=pa_stream_get_format_info(s);
    printf("requested=%s reply=%s\n",want_encoded ? "ac3-iec61937" : "pcm",pa_encoding_to_string(f->encoding)); fflush(stdout); usleep(500000);
    input=fopen(want_encoded ? encoded : decoded,"rb");
    if (!input) { failure=done=1; return; }
}
static void context_state(pa_context *c, void *arg) {
    pa_context_state_t state=pa_context_get_state(c);
    if (state==PA_CONTEXT_FAILED || state==PA_CONTEXT_TERMINATED) { if (!done) failure=1; done=1; return; }
    if (state!=PA_CONTEXT_READY) return;
    pa_format_info *formats[2];
    formats[0]=pa_format_info_new(); formats[0]->encoding=PA_ENCODING_AC3_IEC61937;
    pa_format_info_set_rate(formats[0],48000);
    pa_sample_spec spec={PA_SAMPLE_S16LE,48000,2};
    pa_channel_map map; pa_channel_map_init_stereo(&map);
    formats[1]=pa_format_info_from_sample_spec(&spec,&map);
    stream=pa_stream_new_extended(c,"as21-player",want_encoded ? formats : formats+1,1,NULL);
    pa_format_info_free(formats[0]); pa_format_info_free(formats[1]);
    if (!stream) { failure=done=1; return; }
    pa_stream_set_state_callback(stream,stream_state,NULL);
    pa_stream_set_write_callback(stream,request,NULL);
    if (pa_stream_connect_playback(stream,sink,NULL,(want_encoded ? PA_STREAM_PASSTHROUGH : 0) | PA_STREAM_ADJUST_LATENCY,NULL,NULL)<0) failure=done=1;
}
int main(int argc,char **argv) {
    if (argc!=5) return 2;
    want_encoded=!strcmp(argv[4],"ac3");
    sink=argv[1]; encoded=argv[2]; decoded=argv[3];
    loop=pa_mainloop_new(); context=pa_context_new(pa_mainloop_get_api(loop),"as21-codec-player");
    pa_context_set_state_callback(context,context_state,NULL);
    if (pa_context_connect(context,NULL,PA_CONTEXT_NOAUTOSPAWN,NULL)<0) return 1;
    alarm(15);
    while(!done) pa_mainloop_iterate(loop,1,NULL);
    if (failure) fprintf(stderr,"pulse error: %s\n",pa_strerror(pa_context_errno(context)));
    if (input) fclose(input);
    if (stream) { pa_stream_disconnect(stream); pa_stream_unref(stream); }
    pa_context_disconnect(context); pa_context_unref(context); pa_mainloop_free(loop);
    return failure;
}
