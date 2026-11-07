# libsdl3 3.4.18+ds-1+stereo3d4 (ORDER 15)

The published `+stereo3d3+lc1` source plus four patches for the Linux joystick: the two commits of SDL pull request 14758 (Tomasz Pakuła, EV_BTN) and two of ours (the real EVIOCGBTNCNT number, a log line).
`packages/libsdl3/make-plain.sh` makes the plain source (the published source with Lean Code undone, the patches and the changelog entry) and builds it through `release/build-dh-lean.sh`, which projects, builds, and runs the link and start gate.
Proof of the patches: skills/gamecontroller/references/ev-btn.md.
