sparky-stereo-camera
The Camera page of System Settings (under Multimedia, beside Sound), and its command.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

What it does:
-------------
- The default camera: the session's default video source in PipeWire, kept by WirePlumber (default.configured.video.source), so every program that asks PipeWire for a camera follows it. Programs that list the cameras and pick one themselves (Kamoso takes the first of GStreamer's list) keep their own choice.
- Format, size and frame rate: every one the camera lists, set on the V4L2 device. A camera nobody set starts at its best mode (below).
- The camera's own controls as the driver lists them (integer, boolean, menu, button), set on the device, with a reset to the driver's defaults. Every control is shown; one that cannot be changed now, or is not kept, says why.
- A live preview from PipeWire. A camera with two lenses that sends one packed picture is given its packing (the stereo layer's input list, the same names) and "Show the pair in 3D" draws it as a declared full side by side pair for Stereo KWin.
- What the person chose is kept in ~/.config/sparky-stereo-camera/cameras.ini, and the user service sparky-stereo-camera.service applies it again when the camera is plugged in (a camera starts at its own defaults).
- A refused value, a camera held by another program, a camera that went away, no camera at all and a preview that cannot start are each said on the page; a saved value the camera refuses at plug-in is kept by sparky-stereo-problems once, and cleared when it applies again.

What is kept (0.1.3, ORDER 678):
-------------
Only a setting is saved: a control that has a range (or is a menu or a boolean), that the camera both takes and reports, and that is active when it is read. One rule (keepRule, src/v4l2camera.cpp) answers for the page, the command and the apply step. Each flag of the V4L2 API (VIDIOC_QUERYCTRL, "Control Flags", Documentation/userspace-api/media/v4l/vidioc-queryctrl.rst) and each kind:

| Flag or kind | Clause | Shown | Saved |
|---|---|---|---|
| V4L2_CTRL_FLAG_DISABLED | "permanently disabled and should be ignored by the application" | no | no |
| V4L2_CTRL_FLAG_GRABBED | "temporarily unchangeable, for example because another application took over control" | yes, not offered, with why | no new value; a value saved while it was free is kept |
| V4L2_CTRL_FLAG_READ_ONLY | "permanently readable only" | yes, not offered | no |
| V4L2_CTRL_FLAG_UPDATE | "changing this control may affect the value of other controls" | yes | yes; applied first, and the page reads the others again |
| V4L2_CTRL_FLAG_INACTIVE | "not applicable to the current configuration and should be displayed accordingly" | yes, as reported, not offered until its governing control allows it | no new value; a value saved while it was active is kept and waits |
| V4L2_CTRL_FLAG_SLIDER | "best represented as a slider-like element" | yes | yes |
| V4L2_CTRL_FLAG_WRITE_ONLY | "typically present for relative controls or action controls ... no meaningful value can be returned" | yes, with why | no |
| V4L2_CTRL_FLAG_VOLATILE | "the value of the control changes continuously" | yes, with why | no while active; with INACTIVE it is an auto cluster's manual control (driver-api v4l2-controls, "Auto Clusters") and a setting that waits |
| V4L2_CTRL_FLAG_HAS_PAYLOAD | "a pointer type ... an array, string, or ... a compound type" | yes, not editable | no |
| V4L2_CTRL_FLAG_EXECUTE_ON_WRITE | "required when the control represents an action on the hardware" | yes, with why | no |
| V4L2_CTRL_FLAG_MODIFY_LAYOUT | "may modify the layout of the buffer" | yes | yes; applied before the saved mode |
| V4L2_CTRL_FLAG_DYNAMIC_ARRAY | "a dynamically sized 1-dimensional array" | yes, not editable | no |
| V4L2_CTRL_FLAG_HAS_WHICH_MIN_MAX | "supports getting minimum and maximum values" | yes | yes (no effect on keeping) |
| V4L2_CTRL_TYPE_BUTTON | an action without a value | yes, as a button | no |
| PAN/TILT/FOCUS/ZOOM/IRIS_RELATIVE, ZOOM_CONTINUOUS, PAN/TILT_SPEED | ext-ctrls-camera.rst: "turns the camera ... by the specified amount", "Move the objective lens group at the specified speed": a movement | yes, with why | no (a saved one would move the camera at every plug-in) |
| an integer whose maximum is not above its minimum | no range: nothing to set | yes, with why | no |
| 64-bit integer, bitmask, string | a kind the page cannot change | yes, with why | no |

A default outside its control's own range (the A10's camera: sharpness 0 to 100, default 120) is taken as the driver holds it, clamped and rounded to the step as the V4L2 control framework and uvcvideo do (effectiveDefault): a value is saved when it differs from that.

The apply step (at plug-in, at login and when the page opens): the saved controls that change the picture's layout, then the saved mode, then the other saved controls in passes, each control asked for its flags just before it is set (UPDATE-flagged ones first), an inactive one left for the next pass. So automatic white balance, exposure or focus switched off goes before the value it governs, whatever the controls' ids (uvcvideo answers EACCES to a governed value set while its automatic control is on: uvc_ctrl_is_accessible). A saved setting still inactive at the end keeps its value for when it is active, and is not a problem. A real refusal (a value the camera rejects, a busy camera, a camera gone) is told and kept once, and cleared when it works again.

An entry written by 0.1.0 to 0.1.2 (no version=2 in its group) is cleaned once when its camera is present and the apply had no refusal: a saved value of a control that is not a setting, or that is still inactive after every saved governing control took its value, is removed (such a value was read while the control was not in use), each removal is written to the journal, the problems kept for it are cleared, and the entry is marked version=2. Maintainer scripts never touch a home folder: the clean-up runs in the person's session.

The best mode (0.1.3, ORDER 682):
-------------
Daniel, 2026-11-18: "I think the defaults on the cameras should be for the best resolution then best framerate in this order of priority". A camera with no saved mode (a new camera, or a remembered one whose entry holds no mode) starts at its largest picture and, at that size, its highest frame rate (bestMode); two sizes of one pixel count give the wider one; one size and rate in two formats gives the format that needs no decoding; then the driver's order. It is set at plug-in, shown as the page's first values, and restored by the page's Defaults; the page saves a mode only when the person chose one. "sparky-stereo-camera best NAME" prints it.
A known machine's caveat wins: a reference in sparky-stereo-hardware's table with "owner": "sparky-stereo-camera", "camera": "VVVV:PPPP" (the USB ids) and "formats": [...] names the only formats that camera, in that machine, delivers correctly, and the best mode is chosen among them.
Programs that choose a mode themselves are not changed by this: Qt Multimedia picks its own (QPlatformCamera::findBestCameraFormat: at least 29 frames a second, then the largest), and a PipeWire client that states no preference gets the first mode of the driver's list (spa_v4l2_enum_format).

Command:
-------------
sparky-stereo-camera list | default [NAME] | formats NAME | best NAME | mode NAME [FOURCC WxH FPS] | controls NAME | control NAME CONTROL [VALUE] | reset NAME | packing NAME [ID|list] | save NAME | apply [NAME] | watch

Dependencies:
-------------
pipewire-bin, wireplumber, KDE Frameworks 6 (KCMUtils, KI18n, Kirigami), Qt Multimedia's QML module of the edition (the video output that takes a packing apart)

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container with KF6, Qt Multimedia and PipeWire development packages)

Test:
-------------
autotests/control-rules-test (built and run by the package build): keepRule for every flag, effectiveDefault, bestMode.
tests/rig-proof.sh in a container with PipeWire, WirePlumber and the rig's virtual cameras (skill kde-desktop-defaults, references/camera-page.md and references/camera-controls.md, which has the rows of 0.1.3 with PipeWire's own V4L2 source).
SPARKY_STEREO_CAMERA_SYSFS replaces /sys when the camera's USB ids are read, for a rig's virtual cameras.

Credits:
-------------
The rules follow the Linux kernel's V4L2 documentation, its control framework and auto clusters (v4l2-ctrls, Hans Verkuil) and uvcvideo's control code (uvc_ctrl.c, Laurent Pinchart, with the media subsystem's contributors). Reading the other controls again after a control flagged UPDATE is qv4l2's way (v4l-utils, Hans Verkuil); saving only controls that are neither inactive nor read-only is cameractrls' preset rule (soyersoyer), whose list of controls that move at a speed matches the motion controls here; guvcview (Paulo Assis) was read for comparison. PipeWire's V4L2 source (Wim Taymans and the PipeWire contributors) and Qt Multimedia's camera code (The Qt Company) were read for the mode a program gets. No code is copied.

Install:
-------------
su
apt-get install ./sparky-stereo-camera_0.1.3+lc1_amd64.deb

Uninstall:
-------------
su
apt-get remove sparky-stereo-camera
