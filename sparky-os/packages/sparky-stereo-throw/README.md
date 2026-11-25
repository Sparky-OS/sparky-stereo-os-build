# sparky-stereo-throw: Throw the desktop to Google Cast devices (queue row 81)

A Chromecast, a Google TV or a TV with Google Cast built in becomes one more screen of Stereo KWin.
The person throws the desktop to it from the Throw page in System Settings or with `sparky-stereo-throw throw <id>`.

## What a Throw does

1. **Discovery:** DNS-SD `_googlecast._tcp` through KDNSSD (Avahi); each device as it names itself (TXT `fn`), its model (`md`) and identity (`id`).
2. **The device table** (`data/devices.json`, installed in `/usr/share/sparky-stereo-throw/`): what each model plays in H.264 and the mode its screen gets.
   A model not in the table gets the first Chromecast's limits (1920x1080 at 30 frames a second, H.264 level 4.1), and the person is told once (row 81's review).
3. **The network screen:** the screencast protocol's version 7 request (`stream_virtual_output_with_properties`), its name the device's identity, its description the device's name, the table's mode, not a headset.
   KWin +stereo3d66 makes it a screen like the others: a monitor's 3D formats and eye swap in Display Settings, the person's choice kept per device, "Throw to" in the window menu.
   KWin gives the protocol to this program through `org.sparky.throw.desktop` (`X-KDE-Wayland-Interfaces`, its `Exec` the daemon's installed path).
4. **The stream:** KPipeWire's encoder on the screen's PipeWire node in the codec the device takes (the table's pick: the first one in its row this computer encodes; or the person's choice on the device's page), in the container that follows the codec (Matroska for H.264, fragmented MP4 for HEVC, WebM for VP8 and VP9), on a small HTTP server, a random path per Throw.
   VP9 is not offered yet: KPipeWire 6.7.4's VP9 encoder gives no picture for a live screen (libvpx's 25 frames of lag, which upstream KPipeWire sets to 0), and a VP9 choice is refused with that reason; AV1 waits for an AV1 encoder in KPipeWire.
   A device that connects gets the current group of pictures at once, then the live packets, so a still screen shows too.
   The server listens on this computer's address that faces the device and answers that device only; a connection that sends no request within 5 seconds is closed.
   The picture and the sound travel unencrypted between this computer and the device, as the device's own player fetches them.
5. **The sound:** a PipeWire sink named "Throw: <device>" exists while the Throw runs; the person chooses it as any output, and what plays into it travels in the same stream. Its format is a choice on the device's page: by default the best stereo sound the stream carries that has not failed on that device (24-bit PCM, lossless, in Matroska; FLAC in MP4; Opus in WebM, which carries Opus or Vorbis only), or PCM 16 bit, FLAC, Opus, AAC, Vorbis, MP3, Dolby Digital or Dolby Digital Plus 5.1 (a stereo source then plays on the front speakers; nothing is upmixed). What a device played, or did not start playing, is kept for it by its identity. A speaker or a group gets a Throw of the sound alone (FLAC in Ogg).
   The picture keeps coming on a still screen: KPipeWire encodes the last frame again at the mode's rate, as a receiver's player waits for the next picture of a live stream.
6. **The channel:** CASTv2 over TLS on the device's port, with no device authentication asked (as pychromecast and GNOME Network Displays send); `LAUNCH` of the Default Media Receiver (`CC1AD845`), `LOAD` of the stream as `LIVE`.
   The heartbeat is answered and watched: three missed PONGs and the device is gone, which is said.
   A Throw the device does not play within 60 seconds is ended and said with what the device reported; every message of the channel is in the debug log (`QT_LOGGING_RULES=org.sparky.throw.debug=true`), the stream's token taken out.
7. **Saying what happened:** a running Throw's events through KNotification (`sparkystereothrow.notifyrc`).
   Every failure is kept in the edition's problems engine under `throw:<id>` until a Throw to that device works again, in the person's language.

## What a device lets the PC set

Without the person's Google account: what it says about itself (`/setup/eureka_info?params=device_info,name` and `build_info` on HTTPS 8443, then HTTP 8008, as pychromecast reads it), its receiver's status, and its volume and mute (`SET_VOLUME` on the receiver namespace).
Everything else the Google Home app changes (name, time zone and language, Wi-Fi, restart and reset, ambient screen, guest mode, speaker groups) needs the device's local key (`cast-local-authorization-token`), which only the Home app's own sign-in obtains.
KDE's Online Accounts Google account does not give it yet (row 81's study; skill `stereo-serving`, the Throw reference).

## Proofs

- `tests/castmessage-check.py`: the hand-written CastMessage against pychromecast's generated module, both ways, and chunked messages written from openscreen's `cast_channel.proto` (run by `dh_auto_test`).
- `tests/words-check.sh`: every sentence in nine languages by the names rule and in the translation table, and both checks failing a known bad copy.
- `tests/loopback/`: a whole session in a container with no network: Avahi on a dummy interface announcing software Cast devices (`tests/fake-cast-device.py`), a headless Stereo KWin +stereo3d66, the daemon.
  Its rows: discovery, the stream as the device fetched it (ffprobe), the pair on the thrown screen, the failures, the unknown model, the read side and the volume, and the page in System Settings.

## Licence

GPL-2.0-or-later (Daniel, 2026-10-14), matching KRdp.
GNOME Network Displays (GPL-3.0-or-later) was read, never copied.
