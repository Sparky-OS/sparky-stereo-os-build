sparky-stereo-phone-camera: a phone as the computer's camera.

`sparky-phone-camera` starts DroidCam's client (the DroidCam app on the phone, by Wi-Fi or USB) or scrcpy's camera mode (USB debugging, Android 12 or newer, no app) after saying plainly, in ten languages (lang/*.json), what is missing: the virtual camera module not built for the running kernel, Secure Boot refusing it, no phone on USB, USB debugging not allowed on the phone, a phone that does not answer.
The virtual camera is a v4l2loopback device named "Phone camera" (/etc/modprobe.d/sparky-stereo-phone-camera.conf), loaded by `sparky-phone-camera` when a phone session starts and removed when it ends, through /usr/lib/sparky-stereo-phone-camera/sparky-phone-camera-helper (one word, load or unload) under the polkit action org.sparky.stereo.phonecamera.run (the active local session needs no password). To keep it always listed, add /etc/modules-load.d/phone-camera.conf with the line v4l2loopback.
PipeWire lists it as the camera "Phone camera (V4L2)" and System Settings, Camera shows it like any camera.
With exclusive_caps=1 (a person's choice in the .conf) PipeWire lists the device only after `sparky-phone-camera announce` (skill edition-packaging, references/phone-as-a-camera.md).
KDE Connect is not needed and not depended on.

Tests: `python3 -I tests/test.py` (the cases: the sentences of every failure in several languages, the ten catalogues, announce). `tests/plain-build.sh` builds the package in a container.
