#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
if [ "$1" = "uninstall" ]; then
	rm -f /usr/bin/sparky-stereo-integration
	rm -f /etc/xdg/sparky-stereo-integrationrc
	rm -f /etc/xdg/autostart/sparky-stereo-integration-sync.desktop
	rm -rf /usr/share/sparky/sparky-stereo-integration
else
	mkdir -p /usr/share/sparky/sparky-stereo-integration /etc/xdg/autostart /usr/share/sparky-stereo/integrations.d
	cp bin/sparky-stereo-integration /usr/bin/
	cp share/sparky-stereo-integrationrc /etc/xdg/
	cp share/sparky-stereo-integration-sync.desktop /etc/xdg/autostart/
	cp lang/* /usr/share/sparky/sparky-stereo-integration/
fi
