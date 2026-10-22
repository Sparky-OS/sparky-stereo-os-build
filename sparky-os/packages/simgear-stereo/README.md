# SimGear notification race found during release qualification

The source package `1:2024.1.5+dfsg-1+stereo3d4` failed `test_emesary` with
SIGSEGV during the 20 October 2026 Lean Code migration. The affected authored
header and test had been retained unchanged by the source projector.

The first notifier incremented `receiveDepth` before publishing pending
recipient changes. Another notifier could then read the vector while it was
being modified. The patch holds the existing lock across entry and publication;
`Receive()` calls remain outside the lock. The mutex is recursive because a
registration callback can synchronously notify the same transmitter.

A first repair using a nonrecursive mutex introduced a deadlock in that callback
case. A control test passes on the original source, times out on the first repair,
and passes with this patch. That regression is included in `test_emesary`.

Qualification for `1:2024.1.5+dfsg-1+stereo3d6+lc1`:

- The existing stress test, shortened only in its two base iteration constants
  (9,999,999 to 9,999; still 220 threads and 90 threaded iterations), produced
  11 ThreadSanitizer race warnings on the original implementation. The corrected
  implementation completed with no sanitizer warning and exit status zero.
- The full, unshortened package suite passed all 50 tests.
- The native source projection, binary payload hashes and required HR companion
  passed the Lean Code package checks.

The source package retains the patch and complete authored source. Build a
consumer against the corrected development package: this is a static library
and its public C++ header changes. The migration pins FlightGear's build to
`libsimgear-dev (= 1:2024.1.5+dfsg-1+stereo3d6+lc1)` and verifies that installed
version in its build container. FlightGear's build and physical testing are
separate checks. This repair has not been submitted upstream.
