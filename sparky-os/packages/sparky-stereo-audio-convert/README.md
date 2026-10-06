sparky-stereo-audio-convert
Dolphin's "Convert audio to" menu: FLAC, Ogg Vorbis, Opus, MP3 and WAV through FFmpeg, tags kept.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
bash ffmpeg kdialog

Install:
-------------
su (or sudo)
./install.sh

Uninstall:
-------------
su (or sudo)
./install.sh uninstall

Use:
-------------
Select audio files in Dolphin, right click, "Convert audio to", pick the format.
The new files go next to the originals (an existing file is never overwritten: name-1.ext); a KDE notification says when it is done.
From a terminal: sparky-audio-convert flac|ogg|opus|mp3|wav FILE...
Cover pictures are not copied; every tag FFmpeg can map (title, artist, album, date, track, ...) is.
