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
windows apart. Set `LIFETIME_MSAA=1` to request a four-sample visual in the same fixture. Each draw records `GL_SAMPLES` and requires at least four samples; capture mode may be combined with it.

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


Build `egl-surfaceless-mono.c` with `cc -O2 -Wall -Wextra -Werror -lEGL -lGL`.
It uses the surfaceless EGL platform without a native window, creates ordinary
pbuffers of 64x48, 32x24 and 64x48, and compares every RGB pixel with four
constant quadrant colours. It requires a mono context, reports the renderer
and mapped providers, and returns failure on any mismatch or EGL operation
error. Run against installed predecessor and candidate libraries. This is an
ordinary EGL pbuffer control, not a Wayland window or stereo declaration test.

## Native Wayland EGL windows

`egl-wayland-window.c` checks ordinary windows, two-view windows drawing only
left, and two-view windows drawing both eyes. It binds only `wl_compositor`
and `xdg_wm_base`; Mesa owns all stereo declarations. Generate the xdg-shell
client glue from the installed public protocol and build in a disposable SDK:

```sh
xml=$(pkg-config --variable=pkgdatadir wayland-protocols)/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header "$xml" xdg-shell-client-protocol.h
wayland-scanner private-code "$xml" xdg-shell-protocol.c
cc -O2 -Wall -Wextra -Werror -I. egl-wayland-window.c xdg-shell-protocol.c \
  $(pkg-config --cflags --libs wayland-client wayland-egl egl gl) -o egl-wayland-window
```

Run `egl-wayland-window MODE OUTPUT`, where MODE is `mono`, `left-only` or
`stereo`, in a fresh isolated Wayland compositor for each case, with
`WAYLAND_DEBUG=client`. Do not set DISPLAY or override the installed providers.
The fixture requires the edition's `EGL_EXT_multiview_window`, including for
the ordinary-window control. It checks every drawn GL back pixel and retains
bottom-up RGB arrays. At each `FRAME` line it waits for `next` followed by a
newline, without drawing another frame. Capture before releasing that barrier.
The four stages are first 96x64, first resized 80x48, repeated 80x48 and a new
96x64 native/EGL surface after destruction. An outer runner must bound waits
and preserve failed runs.

`check-egl-wayland.py ROOT --output RESULT` expects `mono`, `left-only` and
`stereo` subdirectories. Each contains `client.stdout`, `protocol.log`, the raw
`STAGE-eyeN.rgb` files, `STAGE.png`, `exit.png`, and a runner `result.json` with
`returncode`, `failure`, `environment`, and `mapped` provider records (each has
`elf_class`). Captures use one 800x600 virtual output, zero stereo depth, no
window decorations or cursor, and full side-by-side screenshots when stereo
is active. The first two cases remain ordinary and byte-identical. Stereo's
left capture must match them, with the right eye exactly 800 pixels to its
right; each eye retains the requested window dimensions. Exit restores black.

The checker independently compares 79,872 raw pixels and 79,872 captured
pixels. It checks actual buffer dimensions and requests: zero declarations
for mono/left-only, one full-SBS declaration for each of the two stereo
surfaces before its first buffer commit, no repeat/resize declaration, two
content destructions, and no viewport writes on the version-2 protocol.
Object numbers may be reused after destruction. Its negative controls reject
missing/changed/duplicate declarations, wrong buffer width, a changed pixel,
swapped eyes and a frozen right eye. This gate covers those native Wayland EGL
behaviors only; it does not establish input/DPI, clipping/overlap, NVIDIA,
Wine or Vulkan behavior.
