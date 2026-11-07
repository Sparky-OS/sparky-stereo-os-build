# debian/copyright of DisplayXR

The `debian/copyright` of Sparky-OS/displayxr-packaging is made from the source trees' own SPDX tags (ORDER 58).

1. Unpack the release tag and the two components (`displayxr-mcp`, `displayxr-common`) as `build.sh` does, into `WORK/t/displayxr-runtime-VERSION`, `WORK/dep-mcp` and `WORK/dep-common`.
2. In a Debian testing container with Debian's `reuse`, write `reuse lint --json` of each tree to `WORK/reuse-lint.json`, `WORK/dep-mcp-lint.json` and `WORK/dep-common-lint.json`.
3. Write the default holders of each project to `WORK/holders-main.txt` (the runtime's NOTICE) and `WORK/holders-dxr.txt` (the components' NOTICE), one per line.
4. `python3 -I make-copyright.py WORK OUT LIBSTEREO_DECLARE/LICENSES/MIT-CMU.txt` writes the file.

`reuse2dep5.py` turns one lint report into Files paragraphs; it is the same script as the edition-packaging skill's `scripts/reuse2dep5.py`.
`make-copyright.py` adds what REUSE cannot see, each paragraph naming the file it was read from.
That is the vendored Wayland protocol XML, the protocol XML a patch adds, the DCO text, the cJSON copy in displayxr-mcp, the stb headers in displayxr-common, the release package with the components of the dashboard's .NET bundle, and the packaging's own paragraph.
The packaging's paragraph comes last, in the shape the edition's provenance step keeps.
After a new release, list again the files that carry copyright lines but no SPDX expression in `reuse lint --json`, and check them by hand, because REUSE gives them the project's licence.
