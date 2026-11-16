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
