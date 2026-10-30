# GLX window lifetime probe

Build `glx-window-lifetime.c` with `cc -O2 -Wall -Wextra -Werror -lGL -lX11` and run it in a disposable headless edition X11 session from an empty output directory.
It creates two ordinary owner windows and two stereo children, draws labelled constant eye colours, and exercises GLX drawable destruction/recreation, X-window reparenting and X-window destruction.
It never writes stereo properties.

`IMMEDIATE` records the first observed owner lists.
`SETTLED` polls only properties, with no rendering or swap during the wait, for at most 200 attempts separated by 5 ms.
All nine `SETTLED` records must have `matched=1` for the owner-lifetime contract.
Both ordinary owners must remain undeclared, and their application event masks must remain zero.
A live child remains listed when only its GLX drawable is destroyed.
Reparenting transfers it to the new owner; destroying the X window removes it before the next swap.

Capture the actual X requests independently when checking write counts.
The two child windows receive one content declaration each, layout 3.
For this sequence, owner-list maintenance performs six writes: two additions, one removal and one addition on reparent, and two removals on destruction.
These maintenance counts are specific to the sequence, not a fixed protocol-wide contract.
No content declaration is inferred from an owner-list update.

The probe preserves the X error from explicitly destroying a GLX drawable after its underlying X window has already been destroyed.
It also retains raw front-eye planes and mapped module paths.
Exit zero means the probe completed; the printed property assertions and independent request/pixel checkers determine acceptance.
Owner-lifetime success does not establish stereo pixel, clipping, overlap, input or DPI correctness.


Set `LIFETIME_CAPTURE=1` to pause at each of the nine lifecycle stages. The
fixture prints `CAPTURE <stage>` and waits for one newline on stdin; it does
not render or swap while waiting. Capture the full side-by-side virtual output
and record actual X geometry while paused. USPosition hints keep the two owner
windows apart. The multisample control is a separate four-sample variant of the fixture.

`check-window-lifetime-capture.py CASE OUTPUT --require-pass` checks all 144,000
raw GL front pixels, all 336,000 captured child-eye pixels, ordinary owner
background pixels, nine lifetime observations, declaration counts and the
actual declaration-before-Present order. Its capture contract is an 800x600
virtual output, side-by-side screen captures, the fixture's requested window
positions, zero stereo depth and no decorations. CASE contains `client.stdout`,
`frameN-eyeE.rgb`, `wire.jsonl` (XRECORD requests with extension metadata and
monotonic timestamps), and `captures.json` (stage, observed geometry, capture
metadata) plus `<stage>.png`. A completed process alone is not a pass. Preserve
old failing rows; do not replace the first frame with a later one. This bounded
fixture does not certify overlap, clipping, input, DPI or other GPU routes.
