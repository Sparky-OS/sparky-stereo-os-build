// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Daniel Campos Ramos
// Queue row 762c test program (never shipped): separate Xlib displays used from several threads at once,
// with the RandR calls DisplayXR's runtime makes. Thread 0 keeps one display open and queries it in a
// loop (as the runtime's depth observer does); the others open a display, query RandR and close it again
// (as its display snapshot and hotplug poll do). Every RandR call goes through libXext's XextAddDisplay(),
// which registers the display with the Generic Event extension (Xge.c), and every XCloseDisplay() runs
// _xgeDpyClose(). With libXext 1.3.4's Xge.c, the close of the last such display frees the shared record
// while another thread writes into it, and the heap breaks (glibc aborts or the program crashes).
// Build: gcc -O1 -g -o xrr-stress xrr-stress.c -lXrandr -lX11 -lpthread
// Env: XRR_THREADS (default 4), XRR_ITERS (default 400), XRR_INIT_THREADS (1: call XInitThreads first;
// libX11 1.8 does it itself). Exit 0 when every thread finished.
#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>

static int iters = 400;

static void query(Display *d)
{
	int eb = 0, erb = 0, maj = 0, min = 0, n = 0;
	if (!XRRQueryExtension(d, &eb, &erb) || !XRRQueryVersion(d, &maj, &min)) {
		return;
	}
	XRRMonitorInfo *m = XRRGetMonitors(d, DefaultRootWindow(d), True, &n);
	if (m != NULL) {
		XRRFreeMonitors(m);
	}
}

static void *persistent(void *arg)
{
	(void)arg;
	Display *d = XOpenDisplay(NULL);
	if (d == NULL) {
		return NULL;
	}
	for (int i = 0; i < iters * 4; i++) {
		query(d);
	}
	XCloseDisplay(d);
	return NULL;
}

static void *churn(void *arg)
{
	(void)arg;
	for (int i = 0; i < iters; i++) {
		Display *d = XOpenDisplay(NULL);
		if (d == NULL) {
			continue;
		}
		query(d);
		XCloseDisplay(d);
	}
	return NULL;
}

int main(void)
{
	// This program is expected to crash on a broken libXext: never let the crash reach the
	// host's core handler (under Valgrind too, which shares this process and sets its own
	// core limit to 0, a value a piped core handler ignores).
	prctl(PR_SET_DUMPABLE, 0, 0, 0, 0);
	const char *e = getenv("XRR_THREADS");
	int threads = e ? atoi(e) : 4;
	e = getenv("XRR_ITERS");
	iters = e ? atoi(e) : 400;
	e = getenv("XRR_INIT_THREADS");
	if (e && e[0] == '1') {
		XInitThreads();
	}
	if (threads < 2 || threads > 32 || iters < 1) {
		return 2;
	}
	pthread_t t[32];
	pthread_create(&t[0], NULL, persistent, NULL);
	for (int i = 1; i < threads; i++) {
		pthread_create(&t[i], NULL, churn, NULL);
	}
	for (int i = 0; i < threads; i++) {
		pthread_join(t[i], NULL);
	}
	printf("xrr-stress done threads=%d iters=%d\n", threads, iters);
	return 0;
}
