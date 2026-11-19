Sparky Stereo audio: high fidelity sound out of the box. The sound system follows the rate of the music or film, a file is converted only when the device cannot take its rate, and then at the highest quality the processor carries.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
pipewire pipewire-bin python3 sparky-stereo-problems wireplumber

What it does:
-------------
Debian's PipeWire runs at 48000 Hz only and converts everything else at quality 4.
This package gives each computer the defaults of Daniel Ramos's design (ORDER item 20, 2026-10-10):

- `default.clock.allowed-rates`: 44100 Hz (the audio CD, Red Book) and 48000 Hz (the professional rate, AES5) on every computer, and every other rate the computer's own sound devices take, read from the kernel's /proc/asound: the HDA codec's converters, a connected display's audio block (the ELD, CTA-861 short audio descriptors) and a USB device's stream list.
  PipeWire then switches the graph to the rate of what plays when a device takes it, so the file is not converted at all.
- A file whose rate no device takes is converted once, to the nearest rate the device takes, at the highest quality this processor carries: the heaviest conversion (192000 to 48000 Hz, stereo) may take at most 20 percent of one core, measured with PipeWire's own resampler at install, and again when the processor changes.
  The quality is 14 where the processor carries it and never below PipeWire's own 4.
- Every device is opened in the best format it offers, which PipeWire already does (24 or 32 bit where there is). A device that takes only 16 bit gets triangular dither (TPDF), so quiet passages and fades stay clean.
- Nothing is forced on a device: PipeWire still refuses a rate the device cannot take.

Read the choices of this computer, in your language: `sparky-stereo-audio show`.
The files are 00-sparky-stereo-audio.conf in /etc/pipewire/pipewire.conf.d, client.conf.d, pipewire-pulse.conf.d and /etc/wireplumber/wireplumber.conf.d (JACK clients run at the graph's rate and are never converted, so they have no file).
They start with 00, so a file of yours with any later name in /etc, or any file in ~/.config/pipewire and ~/.config/wireplumber, wins; the package never edits your files and leaves a file of that name that it did not write as it is, saying so.

Commands:
---------
- `sparky-stereo-audio detect [--write]`: read the devices and say the choices; with --write (root), write the files.
- `sparky-stereo-audio show`: the choices, in plain words.
- `sparky-stereo-audio apply`: in a session, give the running sound system the current list of rates (a user service runs it at login and when the system service has rewritten the list).

A failure (devices that cannot be read, a file that cannot be written, a processor that cannot be measured) is said and kept by sparky-stereo-problems until it is repaired.

Install:
-------------
apt install sparky-stereo-audio

## Headphones and multichannel outputs (0.2.0)

The same engine supplies a WirePlumber policy for per-stream processing.
A multichannel stream to a headphone port or identified Bluetooth headset gets a 5.1 or 7.1 binaural filter.
Stereo keeps its direct path, including while another application uses the filter.
The policy leaves the existing physical-output selection to WirePlumber and the hardware package.
It excludes its own temporary filters from default-output selection, admits the application only after the filter output link is ready, and unloads the module on teardown.
No filter requests a sample rate.

Use `sparky-stereo-audio show` for the choices in your language and `sparky-stereo-audio --help` for command syntax.
For example, in your session:

```sh
sparky-stereo-audio surround --output NODE_NAME --layout 7.1
sparky-stereo-audio surround --output NODE_NAME --headphones yes
sparky-stereo-audio surround --output NODE_NAME --profile /absolute/path/profile.sofa --kind sofa
sparky-stereo-audio surround --output NODE_NAME --profile /absolute/path/profile.wav --kind hesuvi
sparky-stereo-audio surround --output NODE_NAME --profile default --layout auto --headphones auto
sparky-stereo-audio surround --output NODE_NAME --enabled no
```

Choices are saved through WirePlumber's settings API, under `sparky.audio.outputs`.
The engine does not rewrite a person's PipeWire or WirePlumber configuration files or imported audio data.
The default profile is Debian libmysofa's MIT KEMAR normal-pinna SOFA file, measured by Bill Gardner and Keith Martin.
HeSuVi imports use its 14-channel WAV convention, with the mapping in PipeWire's own example; no HeSuVi response file is bundled.
SOFA imports with nonzero separate `Data.Delay` are refused with a translated explanation because PipeWire 1.6.9's spatializer drops those delays.
Embedded response delays, including KEMAR's interaural response, are retained.

Matrix surround, compatible with Dolby Surround and Pro Logic II content, and upmix are explicit options for real multichannel outputs:

```sh
sparky-stereo-audio surround --output NODE_NAME --matrix decode
sparky-stereo-audio surround --output NODE_NAME --matrix upmix
sparky-stereo-audio surround --output NODE_NAME --matrix off
```

Both are off by default, and discrete multichannel streams bypass them.
No reliable stereo flag distinguishes matrix-encoded content from music, so Automatic does not enable either.
The decoder is a passive four-channel matrix following Steve Davies' MPlayer surround coefficients, with a 7 kHz low-pass and 20 ms rear delay.
It has crosstalk and a phantom front center; it does not implement active steering or restore five independently separated original channels.
Upmix uses PipeWire's PSD loopback method, its 12 ms rear delay, 12 kHz center cutoff and 150 Hz LFE cutoff.
Those processing values come from the upstream implementations, not an independent edition standard.

## Encoded audio

PipeWire's ALSA/ACP backend already reads each HDMI output's ELD short audio descriptors and enables its declared formats.
The engine reports those descriptors, exposes per-codec choices, and prevents encoded-only playback from silently falling back to a different output when the selected one cannot accept it.
The player can then decode and retry PCM on the chosen output.
An S/PDIF output without display descriptors gets no new encoded formats automatically.

```sh
sparky-stereo-audio passthrough --output NODE_NAME
sparky-stereo-audio passthrough --output NODE_NAME --codec AC3=off
sparky-stereo-audio passthrough --output NODE_NAME --codec AC3=auto --codec DTS=auto
```

The control uses the same Pulse device-restore extension as pavucontrol.
WirePlumber owns its saved per-route `iec958Codecs`; the engine does not introduce another codec preference store.
The user service `sparky-stereo-audio-monitor` forwards policy failures to the existing problems engine.
New WirePlumber configuration is loaded when its session manager starts; an already running manager must be restarted or the person must log in again after the first installation.
No Sound page files are part of this package.

## References and proof

CTA-861 short audio descriptors, IEC 60958/61937 transport, AES69 SOFA, and ITU-R BS.775 layouts identify the relevant formats and geometry.
The edition's own audio design decides when processing is enabled; no standard mandates that default.
The rendering and transport rigs are in `tests/render-surround.py` and `tests/passthrough/proof.py`.
They use private PipeWire, Pulse and WirePlumber instances, synthetic signals and an ALSA file-writing fixture, without a sound device.
They require NumPy, SciPy, FFmpeg, a compiler and ALSA/Pulse development headers, separate from runtime dependencies.
A virtual sink does not establish a real receiver handshake.
