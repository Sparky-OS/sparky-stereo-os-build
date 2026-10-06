#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/06
# Copyright 2026 under the GNU GPL3 License
if [ "$1" = "uninstall" ]; then
	rm -f /usr/bin/sparky-audio-convert
	rm -f /usr/share/kio/servicemenus/sparky-audio-convert.desktop
	rm -rf /usr/share/sparky/sparky-audio-convert
else
	mkdir -p /usr/share/kio/servicemenus /usr/share/sparky/sparky-audio-convert
	cp bin/sparky-audio-convert /usr/bin/
	cp share/kio/servicemenus/sparky-audio-convert.desktop /usr/share/kio/servicemenus/
	cp lang/* /usr/share/sparky/sparky-audio-convert/
fi
