# skills-mcp

The skills engine of Sparky Stereo OS, written in cgm-zig: one program, three doors.
A person at a terminal (`sparky-stereo-skills find|list|context|sections|commands|run|mcp`), a dialog, and an AI assistant over the Model Context Protocol on stdio (`sparky-stereo-skills serve`) all ask the same engine.

- `docs/TREE.md`: how the tree is laid out and the rules each path follows.
- `docs/CONTRACT.md`: what the engine promises, operation by operation, and the choices made while building it.
- `tests/README.md`: what is tested and how to run it.
- `scripts/`: build the tests, run them in a container, run the program end to end, show a rule failing when it is removed.
- `envs/`: the two container images (build, and a real MCP client).
- `data/golden/` and `data/routing/`: what the Python engine this one replaced answered, recorded as data (its last commit in Sparky-OS/sparky-stereo-os is 9c834ddc312e0c92f4923bfe088e67b3cd54d0bc); no test needs that engine any more.

The packages are in `sparky-os/packages/sparky-stereo-skills`: `sparky-stereo-skills` (the skills, link, the dialog, export) and `sparky-stereo-skills-engine` (this program, amd64), built from one source package.
