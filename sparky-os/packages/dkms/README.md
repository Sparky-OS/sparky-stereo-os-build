dkms for Sparky Stereo OS: Debian's packaging of upstream dkms 3.4.4.

Debian testing and unstable have dkms 3.2.2-1, which reads `/etc/dkms/<module>-<version>.conf` but has no overlay of patches and scripts from `/etc/dkms/<module>/`.
Upstream added that overlay in 3.4.0 (commit f6387d10, Simone Caronni, "Allow patches and scripts overrides in /etc/dkms").
`sparky-stereo-dkms-compat` uses it: its patch for NVIDIA's nvidia-fs 2.29.4 on the PREEMPT_RT kernels lives in `/etc/dkms/nvidia-fs/patches/`, and DKMS copies it into the module's build tree before the build.
So the edition carries the newer dkms on every image, and `sparky-stereo-dkms-compat` installs with it.

DKMS signs every module it builds, with a key and certificate it makes with the `openssl` command the first time (upstream's README, "Module signing": "This requires version 1.1.1 or newer of the `openssl` command to be present on the system"); with Secure Boot a module must be signed before it can be loaded (README, "Secure Boot").
So `dkms` Depends on `openssl` here (ORDER 369). Without it, dkms says "openssl not found, can't generate key and certificate." and installs the modules unsigned. Debian's packaging names openssl in no field; Fedora's recommends it (Paweł Marciniak, 0b971c5).

Modules built unsigned before openssl arrived stay unsigned: `dkms install --force` copies the module already built, and upstream has no command that signs installed modules again (dkms-project/dkms #372, closed as stale on 2026-07-26; Debian #1035707, open).
So when dkms is configured, `/usr/lib/dkms/dkms-sign-unsigned` (debian/scripts, called by the postinst; ORDER 370) builds again every installed module that has a file without the module signature trailer, on a kernel built with module signing: `dkms build --force`, then `dkms install --force`, and DKMS signs it with its key.
Signed modules are left alone, and nothing is built when every module is signed.
It does nothing when DKMS's own policy signs nothing (`try_sign_modules=false`, or a chroot without `try_sign_modules=true`) and says how many modules it left.
A rebuild that fails, or a module DKMS cannot sign (no key and no openssl), is said and kept by `sparky-stereo-problems` with the rebuild as its repair (`dkms-sign-unsigned rebuild MODULE VERSION KERNEL ARCH`); DKMS's built copy is put back, so the module stays installed as it was, and the configuration completes.
`dkms-sign-unsigned check` lists the modules it would build again.
Its messages are in the nine languages, in `debian/problems-lang`, made into journal catalogs at build time.

Sources:
- `debian/` is Debian's packaging as Viorel Cernateanu's merge request proposes it for 3.4.4: https://salsa.debian.org/debian/dkms/-/merge_requests/8, commit 03eded2e6673be1e5889efad13e46fd755cb9458 (open on 2026-11-01). Our changes: `openssl` and `sparky-stereo-problems` in dkms's Depends (debian/control), `sparky-stereo-problems` in Build-Depends, `debian/scripts/dkms-sign-unsigned` with its call in `debian/dkms.postinst`, its install line in `debian/dkms.install` and its catalogs in `debian/rules`, `debian/dkms.postrm`, `debian/problems-lang`, and our changelog entries; `provenance.sh` sets the maintainer fields at build time.
- The upstream tree is https://github.com/dkms-project/dkms, tag v3.4.4, commit cb2790f3d900598d5e55865540f45a049a696e66, tree acfb0ae90df39ecdf90b083183c1f3bc489da3b8, the same tree as the GitHub release tarball that Debian's pristine-tar records. `build.sh` checks both.

Versions and pins:
- `3.4.4-1+sparky3`, the `+sparkyN` of a package the edition carries newer than Debian (as openrgb and protontricks). Lean Code adds `+lc1`.
- The edition's repository is at 1001 (`sparky-stereo`), so this build is the candidate over Debian's 3.2.2-1 (500) and over NVIDIA's 3.4.4-1 in its CUDA repository (100, `91sparky-stereo-cuda`); `sparky-stereo-only-ours` blocks Debian's builds once it is regenerated from a repository that has these packages.
- A person who wants another build writes their own pins, as `sparky-stereo-apt`'s README shows.

Build: `SPARKY_SCRATCH=... bash build.sh OUT` (Docker; the builder image of `release/build-dh-lean.sh`).
When Debian publishes a dkms with the overlay, `openssl` in its Depends and a way to sign modules built unsigned, compare it with this one and return to Debian's.
