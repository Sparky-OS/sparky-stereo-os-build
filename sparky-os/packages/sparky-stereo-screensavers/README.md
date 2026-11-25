# sparky-stereo-screensavers

System Settings' Screensavers page of Sparky Stereo OS (module `kcm_sparkystereo_screensavers`, in Appearance beside Wallpaper).

- The list holds every screensaver the installed packages ship: the stereo catalogue's (gl-stereo-savers, drawn as a pair) and XScreenSaver's 2D ones (one view, the same in both eyes).
- The selected one runs in the small preview; "Full Screen Preview" shows it on the whole screen until a key, a button or a move of the pointer.
- A saver never runs inside System Settings or on the session's display: `sparky-saver-preview` starts it on a private Xvfb and hands the page finished pictures over the stereo show's frame channel.
- The page edits the show's own file, `stereoshowrc` (`Enabled`, `IdleSeconds`, `CycleSeconds`, `DisabledSavers`, `FlatSavers`), and keeps no copy of any value. Screen Locking edits the same three show values.
- The preview's depth follows the person's limits from the desktop's 3D Depth settings: the page asks the layer for the share of one view that puts the sunk limit on the screen at the size the pair is shown, so the small preview and the whole screen show the same pixels of separation.

Build: `OUT=DIR SPARKY_LC_ARCHIVE_DIR=DIR REPO=PUBLISHED_TREE IMAGE=IMAGE SCRATCH=DIR bash build-in-container.sh`.
Translations: `po/tools/translations.py` holds the sentences; `python3 po/tools/make-po.py .` writes the catalogues, and the build checks them.
