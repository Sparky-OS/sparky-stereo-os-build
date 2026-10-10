# tty1 and tty2: main-session guest test

`guest-tty.py` is one self-contained Python 3 script, using the guest's
existing `loginctl`, `busctl`, `runuser` and `systemd-detect-virt` commands.
No Python modules or extra packages are installed. The main session runs
it as root in the headless development VM. It refuses a container or a
machine that systemd does not identify as a VM. The partner never opens
an SSH key or connects to the host desktop.

Prepare one unlocked Plasma **Wayland** session, on a VT other than tty1
or tty2 (for example tty7). Both tty1 and tty2 must be text consoles with
`consoleblank=0`. Use the integrated PowerDevil/defaults packages. The
script requires readable `/dev/vcsa1`, `/dev/vcsa2`, console/framebuffer
power state, and tracefs mounted at `/sys/kernel/tracing`, with syscall
trace events and `sched_process_exec`. Missing prerequisites produce JSON
and exit 2, not a pass.
Do not put another user or workload in the two consoles during the test.

From a root shell in the guest:

```sh
python3 /path/to/guest-tty.py /tmp/tty-positive.json
python3 /path/to/guest-tty.py /tmp/tty-negative.json --negative
```

The positive run takes about 12 minutes. It temporarily changes only
three user AC display keys: dim after 15 seconds, off after 165 seconds,
and lock before off. This maps the desktop's dim 15 minutes, show boundary
135 minutes and screen-off 165 minutes to one second per minute. The
240-second boundary represents the plugged-laptop sleep boundary as a
measurement point. It does not change an automatic-sleep action or timeout,
initiate sleep, launch a GL show, or simulate a lid/battery. The GL show
is still milestone 3; its planned boundary is sampled, not claimed as
an actual drawing event. The laptop sleep cycle is not proved here.

It runs the whole interval with Plasma in front, then with tty1 in front,
then tty2. Every second it checks both consoles' KD_TEXT mode and VCSA
screen/cursor hashes, the kernel consoleblank value and blanked-VT query,
readable framebuffer blank/power and connected DRM DPMS state, and running
screensaver/blanking programs. Foreground text-console power must stay at
its baseline. The initial text framebuffer must be unblanked. The JSON
retains the baseline and dim/show/off/sleep-boundary samples for each phase.
The Plasma phase must show native KWin DPMS Off and native ScreenSaver
locked after the short screen-off deadline. A windowless Wayland reader
observes KWin's DPMS protocol and never sends a DPMS set request. Logind's
active session must match the selected VT throughout.

A private tracefs instance catches non-probe TIOCLINUX calls, execution of
setterm/xset/screensaver programs through `sched_process_exec`, and
write/writev to descriptors already holding either console.
Trace overruns fail the run. This is not a general audit of every possible
relative-path/alias open or inherited descriptor in newly forked processes.
The state checks cover their observable effects at the sample interval.
The kernel's TIOCLINUX API reports the globally blanked VT, not an independent
DPMS setting for each inactive console; the test therefore measures each
text console while it is foreground as well as watching both buffers.

The negative run switches to tty2, records an unblanked baseline, and plants
`TIOCL_BLANKSCREEN` (14). It verifies the kernel actually reports tty2 blanked,
then calls the same detector as the positive run. It must exit **1** with
`negative_injected=true`, `negative_detected=true`, `verified=false`, and
`failure="tty2 was blanked"`. Exit 2 means setup or cleanup failed and is
not an accepted negative result. The script unblanks tty2 in its cleanup.

A positive pass is exit **0**, `verified=true`, all three `completed_vts`,
and `native_kde_screen_off_and_locked=true`, with no mismatch. The original
foreground VT and exact user config bytes, owner and mode are restored in
cleanup; PowerDevil reparses the restored config. It does not unlock the
session afterward. Main copies both JSON files back to `../evidence/tty/`.
Do not call milestone 5 proved until those real guest results are inspected.

`guest-tty-test.py` supplies nine container logic/wire checks, including
the two blanked-console cases, mode/content changes, blanking interval,
power, daemon detection, ioctl return handling, container refusal and
read-only DPMS decoding.
They pass here but do not exercise the guest's kernel ioctls or tracefs.
The UAPI constants come from Linux `include/uapi/linux/tiocl.h`,
`include/uapi/linux/kd.h`, `include/uapi/linux/vt.h`; the DPMS events come
from Plasma Wayland Protocols `src/protocols/dpms.xml` (Martin Gräßlin).
The execution event's filename field is defined in Linux
`include/trace/events/sched.h`. Syscall filename pointers are not used as
string filters.
