# The system test lab (ORDER 22)

One command runs a matrix of rows, each on the edition's components (it must hold) and on stock ones (it must not), in throwaway containers and guests, and writes one report.
The contributor page is `docs/guides/system-test-lab.en.md` in Sparky-OS/sparky-stereo-os, the skill reference `skills/test-bench/references/system-test-lab.md`.

- `lab.py` the runner: `--list`, `--only ROW`, `--kind screens|audio|input|weak`, `--evidence DIR`, `--tree DIR`, `--var NAME=VALUE`, `--strict`.
- `matrix.json` the rows as data.
- `rows/` what a side runs inside its container: the judges, the guest and page scripts.
- `rig/` how the images, kernels and roots are made (`prepare.sh`, `build-audio.sh`, `build-kwin.sh`, `build-page.sh`), the guest assembler and the steps the guests run.
- `tests/test_lab.py` and `tests/test_judges.py` the lab's own tests: `python3 -I tests/test_lab.py`, `python3 -I tests/test_judges.py`.

## Run it

1. `rig/prepare.sh WORK SKILLS_CLONE STAGE_AUDIO REPO_TREE [PLASMA_PA_DEB]` once, with `DOCKER_HOST` set to the Docker the lab may use.
   `STAGE_AUDIO` is a flat apt repository (the `.deb` files and a `Packages` file) holding `sparky-stereo-audio`, until a published tree carries it.
   `PLASMA_PA_DEB` is the edition's `plasma-pa` with the Sound Quality page, until a published tree carries it; without it the page row is skipped and says its images are not built.
2. `python3 -I lab.py --list --var work=WORK --var skills=SKILLS_CLONE` shows each row and what it still needs.
3. `python3 -I lab.py --var work=WORK --var skills=SKILLS_CLONE --evidence DIR` runs them.

`--tree DIR` names the published tree the run is against; it is the tree the report prints, with its Release date, and it defaults to `/var/tmp/sparky-repo-current`.
The compositor, kernel and SDL of "ours" are unpacked from the tree given to `prepare.sh`, not from `--tree`, so for a newer round give `prepare.sh` the new tree and a new `WORK`, remove the images `lab22-kwin-ours:1`, `lab22-kwin-stock:1`, `lab22-page-ours:1` and `lab22-page-stock:1` with `docker rmi` by name, and pass the same tree to `--tree`. `prepare.sh` refuses a `WORK` made from another round, and the report says "NOT the tree of this run" when the two trees differ.

Everything is virtual. No program runs on the host but the runner; apt runs in containers over HTTPS; no module is loaded on the host.
A row that needs `/dev/kvm` runs a guest (QEMU with KVM, no network, no display); every container runs with `--network none`.

## The rows

| Kind | Rows |
|---|---|
| screens | `screens-hdmi3d-edid`, `screens-plain-monitor`, `screens-plain-monitor-2d-edid`, `screens-anaglyph`, `screens-deep-colour`, `screens-eyeorder-hdmi`, `screens-eyeorder-virtual`, `screens-eyeorder-sequential` |
| audio | `audio-follow-44k1-96k`, `audio-16bit-only-device`, `audio-sound-quality-page`, `audio-detect-51-card`, `audio-detect-16bit`, `audio-detect-hdmi`, `audio-detect-headphones` (a fault, queue row 732), and named skips for ORDER 21 and 23 and for Bluetooth |
| input | `input-128-buttons`, and a named skip for the uinput hats |
| weak | the first screens row and the rate following row again under 2 processors and 2 GiB |

A screens row picks its guest script with `env.LAB_PHASE` (`kwin`, `deep`, `eyeorder`, `anaglyph`) and its EDID with `env.LAB_EDID` (`stereo-test`, `stereo-test-2d`, `stereo-eyeorder`); `rows/screens_guest.sh` has the list.
