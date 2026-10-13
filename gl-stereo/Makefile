# SPDX-License-Identifier: GPL-2.0-or-later OR MIT

CC = gcc
CFLAGS = -fPIC -O2 -Wall -Wextra -Werror=implicit -fvisibility=hidden -pthread -g
LDFLAGS = -shared -Wl,--no-undefined
STEREO_CFLAGS = $(shell pkg-config --cflags stereo-declare)
STEREO_LIBS = $(shell pkg-config --libs stereo-declare)
LIBS = -ldl -lGL -lX11 -lm -pthread $(STEREO_LIBS)

SO = libgl-stereo.so

all: $(SO) tests

$(SO): gl-stereo.c egl.inc quad.inc frame-stream.inc
	$(CC) $(CFLAGS) $(STEREO_CFLAGS) $(LDFLAGS) -o $@ gl-stereo.c $(LIBS)

tests: tests/egl-damage tests/state tests/announce tests/quad tests/quads tests/quads-dlist tests/quads-xform savers/starfield savers/announce

savers/announce: tests/announce.c
	$(CC) -DGL_STEREO_SUPPORT_VERSION=1 -O2 -Wall -Wextra -o $@ $< -lX11

savers/starfield: savers/starfield.c
	$(CC) -O2 -Wall -Wextra -g -o $@ $< -lGL -lX11 -lm

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
	rm -f savers/starfield savers/announce

.PHONY: all clean tests install

PREFIX ?= /usr
install: $(SO)
	install -Dm755 $(SO) $(DESTDIR)$(PREFIX)/lib/gl-stereo/$(SO)
	install -Dm755 gl-stereo-run $(DESTDIR)$(PREFIX)/bin/gl-stereo-run
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/LICENSE
	install -Dm644 PACKAGING.md $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/PACKAGING.md

install-savers: savers/starfield savers/announce
	test -x out/bin/rocks
	install -Dm755 savers/starfield $(DESTDIR)$(PREFIX)/lib/gl-stereo/savers/starfield
	install -Dm755 savers/announce $(DESTDIR)$(PREFIX)/lib/gl-stereo/savers/announce
	install -Dm755 out/bin/rocks $(DESTDIR)$(PREFIX)/lib/gl-stereo/savers/rocks
	install -Dm644 savers/controller.py $(DESTDIR)$(PREFIX)/lib/gl-stereo/savers/controller.py
	install -Dm644 savers/frames.py $(DESTDIR)$(PREFIX)/lib/gl-stereo/savers/frames.py
	install -Dm644 savers/catalogue.py $(DESTDIR)$(PREFIX)/lib/gl-stereo/savers/catalogue.py
	install -Dm644 SCREENSAVER-DESIGN.md $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/SCREENSAVER-DESIGN.md
	install -Dm644 savers/README.md $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/SAVERS.md
	install -Dm644 savers/ROCKS-COPYRIGHT $(DESTDIR)$(PREFIX)/share/doc/gl-stereo/ROCKS-COPYRIGHT

install-catalogue:
	python3 plasma/package-catalogue.py out/eligibility/catalogue.json $(DESTDIR)$(PREFIX)/share/gl-stereo/catalogue.json $(PREFIX)
