#!/bin/sh
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/13

if [ "$1" = "uninstall" ]; then
	rm -f /usr/bin/sparky-stereo-locales
	rm -f /usr/share/applications/sparky-stereo-locales.desktop
	rm -f /usr/share/polkit-1/actions/org.sparky-stereo-locales.policy
	rm -rf /usr/share/sparky/sparky-stereo-locales
	rm -rf /usr/share/sparky-stereo-locales
	rm -f /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales
	rm -rf /var/lib/sparky-stereo-locales
else
	cp bin/* /usr/bin/
	cp share/*.desktop /usr/share/applications/
	cp share/*.policy /usr/share/polkit-1/actions/
	mkdir -p /usr/share/sparky/sparky-stereo-locales
	cp lang/* /usr/share/sparky/sparky-stereo-locales/
	mkdir -p /usr/share/sparky-stereo-locales/data
	cp data/language /usr/share/sparky-stereo-locales/data/
	cp share/sparky-stereo-locales/languages.list /usr/share/sparky-stereo-locales/
fi
