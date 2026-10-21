# DKMS compatibility for the stereo kernels

This package supplies a version-specific DKMS override for NVIDIA's
`nvidia-fs` 2.29.4 GPUDirect Storage module. The vendor package and `/usr/src`
remain under NVIDIA's normal update path. No NVIDIA package is pulled in.

Two source files directly include Linux's internal `linux/rwlock.h`.
On PREEMPT_RT that conflicts with the RT lock implementation and fails to
compile. The patch includes the public `linux/spinlock.h` instead, leaving
locking operations unchanged. DKMS 3.4.3 overlays the patch into its build
copy before compilation. The exact-version configuration does not apply to
later vendor versions. Existing patch directives are retained.

Install this compatibility package **before** upgrading kernel images/headers
on a machine with nvidia-fs 2.29.4. The distribution's hardware-support task
includes it; dependency membership alone does not guarantee it is configured
before every kernel's maintainer script in a single large APT transaction.
The migration therefore installs and verifies this package in a separate
first transaction. Live-image builders must stage it before kernel/DKMS setup.

Removing the package retains its conffiles, so the build override remains
active until purge. Purging removes the override, not already built modules. This package does not build,
load, remove or reload modules in its maintainer scripts.

Build with `bash build.sh OUTDIR`. The shared Lean Code builder creates the
`+lc1` archive, its HR companion and a rebuildable source package. The patch
is consumer input and is retained verbatim. Runtime GPUDirect Storage behavior
requires supported hardware; a compile/signature check does not establish it.
