# Held Kopper frames and window lifetime

Build `glx-held-pair.c` with `cc -O2 -Wall -Wextra -Werror -lGL -lX11 -lXcomposite -lxcb -lxcb-present`.
Run `glx-held-pair mono` or `glx-held-pair stereo` in a fresh disposable headless compositor from an empty output directory.
The fixture never writes stereo properties.
It draws address-encoded eyes at 240x140, the first resized 200x120 frame and a second distinct 200x120 frame.
It reads every GL back and front pixel and records actual Present completion events.
At each `CAPTURE` line, capture the compositor before sending one newline to stdin.
The fixture then saves the named packed pixmap, or the ordinary window when it is undeclared.
An outer runner must impose a deadline and preserve failing cases.

`PAIR_NO_FRONT_READBACK=1` omits front-buffer reads to isolate their effect on WSI presentation.
This option does not qualify front readback and must be stated in the result.
Keep the corresponding readback-enabled failures.

`check-glx-held-pair.py CASE` checks the stereo case's raw arrays, packed pixmaps and all delivered eye pixels.
CASE contains `client.stdout`, raw files, `PHASE.png` screen captures and `captures.json` entries with phase and actual window geometry/properties.
The capture contract is a fresh 800x600 virtual output, zero desktop depth and one ordinary window at 20,20 with its child at 10,50.
Provider hashes and raw X requests must be captured independently.
The first Present must use 480x140, and both resized Presents must use 400x120; the child windows remain one eye wide.
The once-per-window content declaration precedes Present, while owner-list writes are counted separately.

Build `kopper-window-lifetime.c` with `cc -O2 -Wall -Wextra -Werror -lGL -lX11 -lxcb -lxcb-present`.
It retains the existing window-lifetime fixture's stages and uses independent Present completion events when the SBC wait is unsupported.
Use `LIFETIME_CAPTURE=1` and optionally `LIFETIME_MSAA=1` as documented in README.md.
The existing `check-window-lifetime-capture.py CASE OUTPUT --require-pass` checks its pixels and owner-list transitions.
A completed process alone is never acceptance.
