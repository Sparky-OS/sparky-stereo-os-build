# KRdp catalogues belong to the package recipe

The code branch `order762b` keeps the paired-headset messages in the source's `i18n()` calls, without changes to `po/` in its rewritten commits. The English source text and the nine translations form the ten-language interface.

The nine translated refusal/revocation entries are already carried by `../krdp-24/overlay/debian/patches/order24-pairing-messages.patch`. This recipe inherits that patch from the pinned +stereo3d11 source and retains it in `overlay/debian/patches/series`. Do not append a second copy or copy whole upstream catalogues into the code fork. The package also retains the earlier translated Throw messages that are not part of the fork's added entries.

For a catalogue-only check, extract the pinned package source, reverse and reapply only the `po/` hunks of the carried patch, then compile each affected `krdpserver.po` with `msgfmt`. Compare the resulting MO files with the installed predecessor's `/usr/share/locale/<language>/LC_MESSAGES/krdpserver.mo`. Check `de`, `es`, `fr`, `ja`, `ko`, `pl`, `pt_BR`, `zh_CN` and `zh_TW`; Japanese has package-owned baseline entries and must not be reconstructed from a missing file in the code fork. Source whitespace and comments are not a translation comparison.

The +stereo3d9 precursor now uses `lc-successor.py --depends` to add its two build dependencies and its runtime dependency to Debian's existing control file. It does not carry a whole authored control overlay. These three replacements preserve the prior generated control byte for byte, including all binary fields; this recipe correction alone does not require a binary rebuild.
