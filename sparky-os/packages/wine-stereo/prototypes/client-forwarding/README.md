# Wine client declaration forwarding

This source proposal makes the edition's Wine 10 `stereo3d/0003` patch distinguish Mesa's version 4 child declaration from the legacy whole-window contract.
It is a complete replacement for that patch, applied at the same position in the series.
Source preparation does not select this directory.

A client carrying `_KDE_NET_WM_STEREO_CONTENT_VERSION = 4` owns a packed pixmap at a one-eye X-window size.
Wine must leave its ordinary whole window undeclared so KWin consumes the client once.
The proposal reads the client version after reading its layout and returns before the existing whole-window writer for version 4.
It leaves absent and older versions on the existing forwarding path and adds no property writer or owner-list update.
It preserves the original declaration patch's authorship and records the correction in its assistance trailer.

The proposal has passed patch application against the original pre-patch inputs, but has not passed compilation or installed runtime qualification.
It does not remove a whole-window property left by an earlier legacy declaration on the same window; a live legacy-to-version-4 transition remains a separate control before any broader lifecycle claim.
No process-exit correction is included.
A wineserver SIGKILL after the fixture's final output remains a failure even when its rendered pixels are exact.

Run the capture checker with Python 3, NumPy and Pillow:

```sh
python3 check-wgl.py /path/to/suite/wgl --output /path/to/new-result.json
```

The input contains separate `nvidia-zink-{32,64}-{mono,stereo}` directories with result, exit, session and capture records from isolated compositor sessions.
Each phase records the full queried X tree, parent IDs, `_NET_CLIENT_LIST`, declarations and versions, named pixmap dimensions and pixels, and the delivered screen.
The checker requires one declared version 4 stereo child, one undeclared managed ancestor at the logical size, no mono declaration, exact packed and delivered eyes, unchanged mono pixels, and successful client and session exits.
Historical captures missing full topology can demonstrate failure but cannot pass the gate.
The checker records every consumed file's SHA256 and reports declaration and exit failures independently of pixel correctness.

These are settled-frame checks at 320×200 and 256×160, with the fixture at (24,24) in an 800×600 virtual output.
They do not certify first-Present timing, declaration event counts, other window types or a physical display.
A passing installed old/new pair and the remaining lifecycle controls are required before integrating this proposal into a package recipe.
