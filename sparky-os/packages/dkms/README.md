dkms for Sparky Stereo OS: Debian's packaging of upstream dkms 3.4.4.

Debian testing and unstable have dkms 3.2.2-1, which reads `/etc/dkms/<module>-<version>.conf` but has no overlay of patches and scripts from `/etc/dkms/<module>/`.
Upstream added that overlay in 3.4.0 (commit f6387d10, Simone Caronni, "Allow patches and scripts overrides in /etc/dkms").
`sparky-stereo-dkms-compat` uses it: its patch for NVIDIA's nvidia-fs 2.29.4 on the PREEMPT_RT kernels lives in `/etc/dkms/nvidia-fs/patches/`, and DKMS copies it into the module's build tree before the build.
So the edition carries the newer dkms on every image, and `sparky-stereo-dkms-compat` installs with it.

DKMS signs every module it builds, with a key and certificate it makes with the `openssl` command the first time (upstream's README, "Module signing": "This requires version 1.1.1 or newer of the `openssl` command to be present on the system"); with Secure Boot a module must be signed before it can be loaded (README, "Secure Boot").
So `dkms` Depends on `openssl` here (ORDER 369). Without it, dkms says "openssl not found, can't generate key and certificate." and installs the modules unsigned. Debian's packaging names openssl in no field; Fedora's recommends it (Paweł Marciniak, 0b971c5).

Sources:
- `debian/` is Debian's packaging as Viorel Cernateanu's merge request proposes it for 3.4.4: https://salsa.debian.org/debian/dkms/-/merge_requests/8, commit 03eded2e6673be1e5889efad13e46fd755cb9458 (open on 2026-11-01). Our changes: `openssl` in dkms's Depends (debian/control) and our changelog entries; `provenance.sh` sets the maintainer fields at build time.
- The upstream tree is https://github.com/dkms-project/dkms, tag v3.4.4, commit cb2790f3d900598d5e55865540f45a049a696e66, tree acfb0ae90df39ecdf90b083183c1f3bc489da3b8, the same tree as the GitHub release tarball that Debian's pristine-tar records. `build.sh` checks both.

Versions and pins:
- `3.4.4-1+sparky2`, the `+sparkyN` of a package the edition carries newer than Debian (as openrgb and protontricks). Lean Code adds `+lc1`.
- The edition's repository is at 1001 (`sparky-stereo`), so this build is the candidate over Debian's 3.2.2-1 (500) and over NVIDIA's 3.4.4-1 in its CUDA repository (100, `91sparky-stereo-cuda`); `sparky-stereo-only-ours` blocks Debian's builds once it is regenerated from a repository that has these packages.
- A person who wants another build writes their own pins, as `sparky-stereo-apt`'s README shows.

Build: `SPARKY_SCRATCH=... bash build.sh OUT` (Docker; the builder image of `release/build-dh-lean.sh`).
When Debian publishes a dkms with the overlay and `openssl` in its Depends, compare it with this one and return to Debian's.
