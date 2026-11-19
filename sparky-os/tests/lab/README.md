# The system test lab (ORDER 22)

One command runs a matrix of rows, each on the edition's components (it must hold) and on stock ones (it must not), in throwaway containers and guests, and writes one report.
The contributor page is `docs/guides/system-test-lab.en.md` in Sparky-OS/sparky-stereo-os, the skill reference `skills/test-bench/references/system-test-lab.md`.

- `lab.py` the runner: `--list`, `--only ROW`, `--kind screens|audio|input|weak`, `--evidence DIR`, `--tree DIR`, `--var NAME=VALUE`, `--strict`.
- `matrix.json` the rows as data.
- `rows/` what a side runs inside its container: the judges, the guest scripts.
- `rig/` how the images, kernels and roots are made (`prepare.sh`), the guest assembler and the programs run in the guests.
- `tests/test_lab.py` the runner's own tests: `python3 -I tests/test_lab.py`.

Everything is virtual. No program runs on the host but the runner; apt runs in containers over HTTPS; no module is loaded on the host.
