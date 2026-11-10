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

## ORDER 414 (2026-11-05): browser +stereo3d7 and KWin +stereo3d43

4. `build-browser.sh` now makes sparky-stereo-browser 6.7.5-0+stereo3d7+lc1: the stereo3d5+lc1 source plus `browser/0001` and `0002` as
   before and `0003` (Gecko 075e18be19 to 81fecb57fb: the flat WebXR modes, the CSS depth property, the VR quit fix) and `0004` (the
   3D Display strings in the nine languages), `Depends: libstereo-policy1 (>= 1.15.0)`, `de` in the multi-locale package, the
   changelog entries for +stereo3d6 and +stereo3d7. `BROWSER_JOBS` (default 8) sets the threads. The patches were applied to the orig's
   own files and the result compared byte for byte with the Gecko commit's files (33 of 33 equal).
5. `../kwin/build-43.sh`: kwin 4:6.7.4-2+stereo3d43+lc1 from the +stereo3d42+lc1 source (`prepare-source-43.sh`, patches `s43-*`:
   the output's depth limits from libstereo-policy and protocol 5), Build-Depends libstereo-policy-dev (>= 1.15.0). The archive link
   gate needs libstereo-policy1 (>= 1.15.0) in an archive: until lane 411's stereo-layer 1.15.0 is published, a fixture archive
   with a throwaway key holds the stereo-layer debs (SPARKY_LC_ARCHIVE_DIR with a second source in sources.json); rebuild the
   gate against the published library before publication.

## ORDER 414c (2026-11-06): browser +stereo3d7 again, the depth from KWin

`browser/0003` now runs to Gecko 73841dee65: the browser binds `kde_stereo_content_manager_v1` up to version 5 and follows
`kde_stereo_depth_v1` (awake, and the sunk and popped limits of the output the window mainly sits on, live); a click lands where a
depth element is drawn; scroll frames inside it move with it in both copies; a KWin whose protocol is older than 3 leaves the pages
on libstereo-policy's default with a console notice. The recipe is unchanged otherwise (`BROWSER_JOBS=4`, `SIBLINGS_DIR`).
The stage folder 414c-browser-7 supersedes 414b-browser-7.

## ORDER 414d (2026-11-06): browser +stereo3d8, the stereo window rule, popups as popups, about:support

`browser/0003` now runs to Gecko 9e5eab05c5: a popped element that touches the output's edge stays at the screen (KWin's
`output_edges`, the viewport's flush sides; a page in full screen), every popup (the `<select>` list, tooltips, form autocomplete, permission
prompts) is an xdg_popup of its own surface under Stereo KWin (`widget.wayland.popups-as-xdg-popups`), and about:support says that
DMABuf WebGL on NVIDIA is forced on by `widget.dmabuf-webgl.stereo-nvidia.enabled` (or blocked, saying the preference is false).
`build-browser.sh` makes 6.7.5-0+stereo3d8+lc1 (`browser/changelog8.top`, `0002` states the commit and the version). The call is as for
+stereo3d7: `BROWSER_JOBS=4 SIBLINGS_DIR=.../siblings-1171 SPARKY_LC_ARCHIVE_DIR=.../archive SPARKY_REPO_DIR=/var/tmp/sparky-repo-current`.

## ORDER 473u (2026-11-10): browser +stereo3d14, the camera hack from the person's depth limits

`browser/0013` is Gecko 6be1abb34e to ac402b8caa (branch order473u of the fork): a WebGL canvas drawn once out of view shows both eyes,
the left eye is the page's own camera (a 2D output shows what the page draws), the zero-parallax plane follows the scene inside the
person's popped limit (the camera hack and the flat WebXR display), the hack's separation is the sunk limit of the window's
`kde_stereo_depth_v1` depth_limits over 1920 pixels scaled by the 3D Canvas menu's Less, Normal, More and Most
(`webgl.stereo-camera.separation-from-limits`), and a depth buffer that cannot be read is said once on the page's web console.
`0014` states the commit and the version, `changelog14.top` the entry. The recipe starts from the +stereo3d13+lc1 source (the stage folder of
that build is the published folder), is called as for +stereo3d8 with `BROWSER_JOBS=4`, and names its container with `BROWSER_CONTAINER`.

ORDER 473u round 3 (2026-11-10): the edition's browser has no setting for the depth of a 3D picture, the screen plane or the kind of device (Daniel: a program's 3D options are only enabling 3D, the render resolution and a shortcut to Display Settings; the rest is KWin's). `browser/0013` now runs to Gecko 1981fbd3f7: the 3D Canvas and 3D Display menus' Less, Normal, More and Most, the screen plane choices and the Flat TV, Flat headset and VR over the phone modes are removed with their preferences, `FlatMode()`, the `stereo-camera-depth` permission and strings; `0015` removes the strings from the nine languages and adds the Display Settings item's label. The device chooser stays in the fork's branch `order473u-upstream-offer` (Gecko fe59fb1c3a), for an offer to Waterfox, not in this package.
