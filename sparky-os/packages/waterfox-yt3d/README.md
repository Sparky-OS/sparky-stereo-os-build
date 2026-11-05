# ORDER 193: YouTube's yt3d marks, three packages (6a-2)

Three recipes, run in this order, each in the Lean Code migration container with the build record's host facts
(`sparky-os/repo/build-provenance.sh`), never on the host:

1. `build-stereo-layer.sh`: stereo-layer 1.13.0-1+lc1, the whole cohort (libstereo-av1, -layer1, -policy1, -dibr1, their -dev, -dbgsym
   and HR packages: 16 archives), from the release tag of the stereo-layer clone, whose own `debian/` is the packaging. libstereo-policy
   1.13.0 holds the one reader of the yt3d keywords (`stereo_policy_site_mark`, docs/yt3d.md). The link and start gate runs against the
   published 1.12.0-5+lc1 builds (`SPARKY_LC_ARCHIVE_DIR`: sources.json and its public keyrings, `sparky-os/lean/archive.md`).
2. `build-plasmatube.sh`: plasmatube 26.08.1-1+stereo3d5+lc1, the +stereo3d4 plain source plus `plasmatube/0006-...patch` (PlasmaTube calls
   the shared reader instead of keeping a table of the tags; the first form is right eye first and `swap` makes it left eye first, which
   fixes "3D Maestro" shown with its eyes swapped), `Build-Depends: libstereo-policy-dev (>= 1.13.0)`, `Depends: libstereo-policy1 (>= 1.13.0)`.
   The libstereo-policy 1.13.0 archives of step 1 are installed before the build dependencies and given to the gate as the siblings.
3. `build-browser.sh`: sparky-stereo-browser 6.7.5-0+stereo3d6+lc1, the published stereo3d5+lc1 source package with its orig tarball
   unchanged (so no pool conflict) plus `browser/0001` (the site mark, Gecko commit 075e18be19 over the orig's b1d115f8d3) and `browser/0002`
   (SOURCE.edition.json names that commit), the changelog entries, `Depends: libstereo-policy1 (>= 1.13.0)`, `MOZ_SOURCE_CHANGESET` and the
   vendor baseline's commit; the new source package is made with `dpkg-source -b` and the build runs from it.
