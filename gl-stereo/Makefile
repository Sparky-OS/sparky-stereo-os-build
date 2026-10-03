# SPDX-License-Identifier: GPL-2.0-or-later OR MIT

CC = gcc
CFLAGS = -fPIC -O2 -Wall -Wextra -Werror=implicit -fvisibility=hidden -pthread -g
LDFLAGS = -shared -Wl,--no-undefined
STEREO_CFLAGS = $(shell pkg-config --cflags stereo-declare)
STEREO_LIBS = $(shell pkg-config --libs stereo-declare)
LIBS = -ldl -lGL -lX11 -lm -pthread $(STEREO_LIBS)

SO = libgl-stereo.so

all: $(SO) tests

$(SO): gl-stereo.c egl.inc quad.inc
	$(CC) $(CFLAGS) $(STEREO_CFLAGS) $(LDFLAGS) -o $@ gl-stereo.c $(LIBS)

tests: tests/egl-damage tests/state tests/announce tests/quad tests/quads tests/quads-dlist tests/quads-xform

tests/egl-damage: tests/egl-damage.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lEGL -lX11

tests/state: tests/state.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lX11 -pthread

tests/announce: tests/announce.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lX11

tests/quad: tests/quad.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lX11

tests/quads: tests/quads.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lX11

tests/quads-dlist: tests/quads-dlist.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lX11

tests/quads-xform: tests/quads-xform.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lX11


clean:
	rm -f $(SO) tests/egl-damage tests/state tests/announce tests/quad tests/quads tests/quads-dlist tests/quads-xform

.PHONY: all clean tests install

PREFIX ?= /usr
install: $(SO)
	install -Dm755 $(SO) $(DESTDIR)$(PREFIX)/lib/gl-stereo/$(SO)
	install -Dm755 gl-stereo-run $(DESTDIR)$(PREFIX)/bin/gl-stereo-run
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/LICENSE
	install -Dm644 PACKAGING.md $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/PACKAGING.md
