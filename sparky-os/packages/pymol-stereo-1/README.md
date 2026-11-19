# pymol-stereo-1 (ORDER 50, step 2)

PyMOL 3.1.0+dfsg-1+stereo3d1+lc1, Debian unstable's own source (carried: PyMOL left testing for the flaky autopkgtest of bug 1137219, a riscv64-only segmentation fault; 20 of 20 amd64 runs pass) with `patches/stereo-1-one-stereo-output.patch`.

Design followed:
- /K3D/CLAUDE.md: one output, full side by side handed to Stereo KWin (here the quad buffer Mesa packs); a program's 3D options are only Enable 3D, render resolution per eye and a shortcut to Display Settings.
- stereo-integrations-auto-enable (Daniel, 2026-10-14): Enable 3D is on by default. On a screen with no quad buffer visual PyMOL stays 2D and says nothing; it tells the person (ten languages) only when they turned 3D on themselves, or when a visual exists and the pair cannot be made. The person's own off is kept.
- one-separation-one-place: PyMOL's own stereo_angle and stereo_shift are untouched.

`build.sh DEBIAN.dsc WORK` (disposable container with the build dependencies, nodejs, node-acorn, gcc, perl, python3-yaml, bubblewrap; docker with `--security-opt seccomp=unconfined apparmor=unconfined systempaths=unconfined`; SPARKY_LC_* from the build record route), then `lean.release check-debs`.
Role line: `lists/roles.tsv`; carry row: `lists/carried-from-unstable.tsv`.
