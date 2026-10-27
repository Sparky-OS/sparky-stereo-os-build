# Shared native video input package

`build-native.sh SOURCE_PACKAGE_DIR OUTPUT_DIR TOOLKIT_DIR` starts with the
published 1.12.0-1 source descriptor, applies the accepted content-inspection
patch and the additive native-input patch, prepares Lean Code, creates one
1.12.0-4+lc1 source descriptor, and builds the complete shared-library cohort.
The AV, layer, policy and DIBR runtime/development packages, debug symbols and
required HR companions are all included. The native pairing and shared anaglyph
policy tests run during the build.

The content service and command-line probe remain gated by BUILD_CONTENT_ENGINE,
off until the later application-selection integration. A test probe linked to
the installed libstereo-av is sufficient to exercise its public inspection API;
a probe compiled with copies of the library source is not installed proof.

Revision -4 exposes the existing approximate anaglyph equations to video
consumers without forcing RGB32 conversion, rejects invalid colour-pair values,
and clears a stale container anaglyph field when codec packing replaces it.
It retains -3's independent per-track metadata initialization. Bino +8 requires
both libstereo-layer1 and libstereo-av1 >= 1.12.0-4+lc1. The additive APIs preserve
existing callers and the picture reconstruction's integer results.

Gate all sixteen archives and required HR companions with check-debs. Run the
unchanged archive-backed check-link against the actual published cohort: layer,
policy and DIBR -1, AV -3 at this build's signed snapshot. Keep exact indexed
hashes, predecessor archives, resolver/runtime receipts and meaningful LC-marker
and missing-ELF-dependency negatives. Use signed Debian Forky, deb-multimedia
testing and edition archive sources, private roots and the documented disk floors;
no host package installation or gate allowance is needed.

Installed proof includes real MV-HEVC samples and lifecycle controls, every
inspection fixture, automatic/explicit multi-track selection, four conflicting
codec/container marks, and independent reconstruction equations for all three
colour pairs and both eyes. Preserve the old installed red controls. These
anaglyph approximations cannot restore discarded full-colour eye information.
