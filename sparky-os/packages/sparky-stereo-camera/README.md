sparky-stereo-camera
The Camera page of System Settings (under Multimedia, beside Sound), and its command.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

What it does:
-------------
- The default camera: the session's default video source in PipeWire, kept by WirePlumber (default.configured.video.source), so every program that asks PipeWire for a camera follows it. Programs that list the cameras and pick one themselves (Kamoso takes the first of GStreamer's list) keep their own choice.
- Format, size and frame rate: every one the camera lists, set on the V4L2 device.
- The camera's own controls as the driver lists them (integer, boolean, menu, button), set on the device, with a reset to the driver's defaults.
- A live preview from PipeWire. A camera with two lenses that sends one packed picture is given its packing (the stereo layer's input list, the same names) and "Show the pair in 3D" draws it as a declared full side by side pair for Stereo KWin.
- What the person chose is kept in ~/.config/sparky-stereo-camera/cameras.ini, and the user service sparky-stereo-camera.service applies it again when the camera is plugged in (a camera starts at its own defaults).
- A refused value, a camera held by another program, a camera that went away, no camera at all and a preview that cannot start are each said on the page.

Command:
-------------
sparky-stereo-camera list | default [NAME] | formats NAME | mode NAME [FOURCC WxH FPS] | controls NAME | control NAME CONTROL [VALUE] | reset NAME | packing NAME [ID|list] | save NAME | apply [NAME] | watch

Dependencies:
-------------
pipewire-bin, wireplumber, KDE Frameworks 6 (KCMUtils, KI18n, Kirigami), Qt Multimedia's QML module of the edition (the video output that takes a packing apart)

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container with KF6, Qt Multimedia and PipeWire development packages)

Test:
-------------
tests/rig-proof.sh in a container with PipeWire, WirePlumber and the rig's virtual cameras (skill kde-desktop-defaults, references/camera-page.md)

Install:
-------------
su
apt-get install ./sparky-stereo-camera_0.1.0_amd64.deb

Uninstall:
-------------
su
apt-get remove sparky-stereo-camera
