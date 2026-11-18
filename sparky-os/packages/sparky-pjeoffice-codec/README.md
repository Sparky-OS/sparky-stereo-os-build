sparky-pjeoffice-codec
Private FFmpeg 5.1 decoder libraries for PJeOffice Pro's video cutter.

Copyright: FFmpeg developers (LGPL-2.1-or-later); packaging by Daniel Ramos (Capitain Jack), see copyright.

Why:
-------------
The cutter of PJeOffice Pro plays video through the JavaFX Media that ships with the program. Its native loader looks for libavcodec and libavformat of the major versions 53 to 59; Debian's FFmpeg is major 63, so the cutter showed a generic error for every MP4 (measured on 2026-11-18, ORDER 18). These are FFmpeg 5.1.10's own shared libraries, so it finds libavcodec.so.59 and libavformat.so.59.

What:
-------------
- The source is the signed release ffmpeg-5.1.10.tar.xz, unmodified. build.sh fetches it from ffmpeg.org, checks its SHA-256 and the signature of the release key (fingerprint FCF986EA15E6E293A5644F10B4322F04D67658D8), and stops on any difference.
- configure: --disable-everything, then the decoders, demuxers and parsers of the formats JavaFX Media plays (H.264 and AAC in MP4, FLV with VP6, MP3, WAV, AIFF), the file protocol, no network, no programs, no x86 assembly.
- The libraries (libavutil.so.57, libswresample.so.4, libavcodec.so.59, libavformat.so.59) are in /usr/lib/sparky-pjeoffice/codec with the run path $ORIGIN. Nothing else is installed and no system library is replaced. Only /usr/bin/pjeoffice-pro puts that folder on LD_LIBRARY_PATH, for the signer's process; the system's FFmpeg executable the cutter calls to cut keeps its own libraries.
- FFmpeg 5.1 is the oldest line the project still lists as supported on its download page; when it ends, the cutter's playback is the program's own matter (it only looks for these versions).

Build:
-------------
OUT=/path bash ./build-in-container.sh (see sparky-pjeoffice's recipe for the variables).
