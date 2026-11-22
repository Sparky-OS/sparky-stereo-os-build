# Installed package lifecycle

Run `package-lifecycle.sh` only inside the disposable packaging container, with
network disabled, at most four CPUs and core limit 1. Mount a fresh writable
`/out`, the verified signed mirror at `/archive` (its `sources.json` uses these
guest paths), the published repository at `/published`, accepted Graphics and
previous Partners closures at `/row70`, the Vibe integration closure at
`/vibe-stage`, and the new qualified packages at `/stage`, all inputs read-only.

`PLAN_ONLY=1` records the baseline APT solve and package URIs without installing.
`BASELINE_ONLY=1` installs that accepted baseline and stops before the witnesses.
The full run records the real upgrade and removal, asserts their `Inst`/`Remv`
sets, checks installation leaves the unit disabled and both programs absent,
and checks five synthetic personal files are unchanged after removal. None is
speech-model data and no recognizer is run. This packaging proof does not cover
turning the installed page on and off over playing audio.

The mirror needs signed binary indexes; `target=Packages` prevents the newly
installed AppStream and apt-file configurations requesting optional icon and
Contents indexes unrelated to this dependency solve. Signatures, hashes and
APT's normal dependency constraints remain enabled.
