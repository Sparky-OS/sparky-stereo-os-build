# Effective idle timeline fixture

Run only inside the lane's unprivileged, CPU-limited Docker container.
The fixture starts a pixman headless Weston parent with its native fake seat,
the development KWin Wayland package, the packaged PowerDevil daemon and a
read-only KScreen DPMS observer. Both D-Bus buses, all Wayland sockets,
UPower and logind belong to the fixture. It mounts no host display, input,
DRM device, PipeWire socket or session bus.

`HEADLESS_SDK` points to an extracted runtime prefix containing Weston,
the development KWin packages, its dependencies, libfaketime, the Qt Wayland
layer-shell integration, and Python dbusmock. This lane's prefix is
`work/sdk-extra`. `POWERDEVIL_PREFIX` defaults to the extracted daemon,
core and data payload at `work/power-package-payload/usr`.
`TIMELINE_DEFAULTS` defaults to the extracted defaults package's
`work/defaults-payload/etc/xdg`. `TIMELINE_OBSERVER` defaults to
`work/timeline-observer`; `build-observer.sh` builds it with Qt and KF6ScreenDpms.

`run.sh` checks the native profile through PowerDevil's D-Bus interface before
measuring. It uses Solid's native fake hardware and private UPower properties.
`TIMELINE_CASE` is desktop, laptop, battery or eco. Give each case a distinct
`TIMELINE_RUN` directory. The AC cases require `TIMELINE_DURATION=252`; the
battery default is 38 and eco uses 17. KWin and PowerDevil run with a separately
calibrated 60x clock, so 165 minutes become 165 seconds and four hours become
240 seconds. The observer and mock services retain real clocks.

After the run, invoke `python3 check.py CASE RUN_DIRECTORY`. It compares the
real DPMS transition and native logind locked hint with the expected timeout,
requires lock before screen-off, checks native suspend requests and their
timing, and rejects hibernate requests. Desktop observation extends past
four hours and must contain no suspend request. It also checks native DPMS
support, profile-specific timeout registration and absent brightness hardware.
These are mock logind requests, not physical sleep/resume cycles. The backend
cannot prove brightness changes. KWin uses the real locker's built-in fallback
because this fixture does not provide a full Plasma look-and-feel.

For the negative control, copy the defaults to another fixture directory,
replace the three `LockBeforeTurnOffDisplay=true` entries with false, and run
battery with that directory as `TIMELINE_DEFAULTS`. The checker must fail the
lock assertion while native DPMS still turns the output off. The fixture must
never be run against a real display or host system/session bus.
