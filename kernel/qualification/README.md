# Kernel build and qualification

These tools build the edition's kernel flavours as Lean Code source packages (`kernel/lean`) and qualify each one in isolation: a boot in a QEMU guest with its feature probes, and the DKMS module matrix, before anything reaches a machine.
They built and qualified kernel build 9 (`7.3.0~rc6-9+lc1`) on 20 October 2026. From build 13 the upstream tag comes from the source manifest and its version strings from `kernel/lean/upstream.py`, which pins every accepted tag to its verified commit; a new tag is added there.

Settings come from the local configuration (`sparky-os/config/build.conf.example`); the shared helpers are in `sparky-os/release`.

| Tool | What it does |
|---|---|
| `kernel-source-preflight.py` | Collects the native-consumer failures of the base kernel source, read-only. |
| `prepare-kernel-source.py` | Exports the accepted feature set and patch series into a source package for one flavour. |
| `run-kernel-smoke.py` | Builds the source package once as a disposable smoke test. |
| `run-kernel-migration.py` | Builds the three flavours one after another, signing with the Secure Boot key. |
| `prepare-kernel-validation-tools.py` | Prepares the container with QEMU, OVMF, swtpm and the DKMS tools. |
| `prepare-qemu-kernel-checks.py` | Qualifies the installed QEMU candidate as the guest's virtual machine. |
| `qualify-kernel-boot.py`, `kernel-qualification-inner.py` | Boot one kernel in the guest and run its feature probes. |
| `qualify-kernel-dkms.py`, `kernel-dkms-inner.py` | Build the edition's and the host's DKMS modules against one kernel. |
| `run-kernel-build.py` | Builds one prepared flavour unsigned (no key mounted); `prepare-kernel-source.py` takes `--counter`, `--source-dir` and `--manifest` for a build after 9. |
| `sign-kernel-image.py` | The release coordinator's step: Secure Boot signs the image inside an unsigned `linux-image` package and keeps the Lean Code manifest, marker and md5sums true; checks the result with `check-debs`. |
| `qualify-kernel-unsigned.py` | Boots a freshly built, still unsigned kernel in the validation guest (the bench signs it with its own throw-away key) and runs the feature matrix. |
| `run-kernel-qualification-queue.py` | Runs both checks after each kernel finishes; never publishes or installs. |
