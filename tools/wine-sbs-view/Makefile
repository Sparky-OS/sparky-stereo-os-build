PREFIX ?= /usr
CC ?= cc
CFLAGS ?= -O2 -g
PACKAGES = x11 xcomposite xdamage stereo-declare
CPPFLAGS += $(shell pkg-config --cflags $(PACKAGES))
LDLIBS += $(shell pkg-config --libs $(PACKAGES))
LANGUAGES = en pl pt_BR fr de ja ko zh_CN zh_TW
CATALOGS = $(LANGUAGES:%=po/%.mo)
all: wine-sbs-view $(CATALOGS)
wine-sbs-view: main.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)
po/%.mo: po/%.po
	msgfmt --check -o $@ $<
install: all
	install -Dm755 wine-sbs-view $(DESTDIR)$(PREFIX)/bin/wine-sbs-view
	for lang in $(LANGUAGES); do install -Dm644 po/$$lang.mo $(DESTDIR)$(PREFIX)/share/locale/$$lang/LC_MESSAGES/wine-sbs-view.mo; done
clean:
	rm -f wine-sbs-view $(CATALOGS)
.PHONY: all install clean
