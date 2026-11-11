# A KDE licence window during installation

This small executable embeds `DebconfKde::DebconfGui`, the same Qt6 renderer and protocol used by Debian testing's `debconf-kde-helper` 1.2.1-1 and `DEBIAN_FRONTEND=kde`.
It gives the core-font licence explicit Accept and Decline actions. Decline has keyboard focus by default. Closing the licence submits false through debconf, so installation can continue without Microsoft fonts and show the retry instructions.
It never writes a consent database or supplies an acceptance preseed.

Calamares runs it in the live environment. The target's apt uses the library's documented `DEBIAN_FRONTEND=passthrough` / `DEBCONF_PIPE` socket interface, with the socket under `TARGET/run`.
Using `DEBIAN_FRONTEND=kde` directly in the chroot would start the helper there and require the live Wayland runtime socket inside the target.
The surrounding settings package renders ORDER 399's existing declaration/assessment in a graphical notice and reports refusal or failure. Only that already-displayed transaction suppresses the duplicate terminal warning.
The text installer retains readline.

The licence note and false-default boolean are queued before one debconf GO.
The embedding adapts the stock widget's generic OK/Cancel radio choices, using the inspected 1.2.1 widget names; retain the actual window tests when updating libdebconf-kde.
The Microsoft legal text is retained, and the question, actions and outcomes are localized in the settings package's ten languages.

Build with the native edition pipeline in `build.sh`, an empty `WORK`, the recipe's `SOURCE_DATE_EPOCH`, and the documented `SPARKY_LC_ARCHIVE_CONFIG` / `SPARKY_LC_SCRATCH` for its link/start gate.
The native binary is separate from the script-only settings adapter.
Run `tests/corefonts-gui.py` from the settings recipe in a private KWin Wayland session with a copied disposable target.
When no render device is authorized, virtual KWin uses QPainter and ScreenShot2 cannot capture it; `tests/capture-qpainter.py` reads that private compositor's actual output buffer and records its source and hash.
