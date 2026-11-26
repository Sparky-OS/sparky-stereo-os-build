# ORDER 46 infrastructure catalogues

Use the current signed source descriptor and all its members. The checked source
versions are listed below. The KWin and KRdp patches use the staged sources
shown in the table; the original measurements used the published +59 and +8. Source-built successors use the normal
`catalogue-rebuilds/build.sh WORK SOURCE_DIR DSC PREVIOUS_DIR ENTRY PATCH`
invocation. `ENTRY` is under `entries/`. Supply the named patch from
`sparky-os/translations/` as `PATCH`; the recipe appends it to the quilt series
after the edition's existing patches. The changelog entries are for the next
build from the stated source.

KWin and KRdp use the existing packaging lanes. Apply the named quilt patch
after their series. For KRdp apply the `.packaging.patch` to the source root
while preparing `debian/`, before generating the .dsc. Its Spanish helper PO
goes in the directory already selected by `DIRECT_WIFI_TRANSLATIONS`. Compare
keys with the receiving staging tree first and retain any already equivalent
entries. For KWin the KCM JSON also supplies the generated Settings desktop
entry.

The Throw and Catch names also apply to translations already in the published
source. Append `krdc-throw-catch-names.patch`, `kwin-throw-catch-names.patch`
and `krdp-throw-catch-names.patch` to the corresponding source's series after
its ORDER 46b patch. For KRdp apply `krdp-packaging-throw-catch-names.patch`
alongside the earlier packaging patch before producing the .dsc. These
supplemental patches update the eight locales already in the source; the
original catalogue patches provide the Spanish keys. Compare the exact values
and replay against the receiving version using its signed source descriptor.
The published-base replay does not qualify the later KRdp catalogue context.

The Calamares branding package builds its updated slide catalogues from the
TS files checked in beside `slides-20261016.json`.

For the browser, apply the `.packaging.patch` to the source root while
preparing `debian/`, before generating the .dsc. This localizes the packaged
desktop and AppStream files that the browser recipe already installs.

`patch --batch --fuzz=0 -p1 -i PATCH` applies the packaging patches from the source
root. Use an absolute patch path. These are changes to Debian packaging and
belong in the Debian tarball when producing the next source descriptor.

| Source | Exact checked source | Receiving recipe or build | Patch | Changelog entry |
|---|---|---|---|---|
| `command-not-found` | `23.04.0-3+sparky1+lc1` | `successor to 23.04.0-3+sparky1+lc1` | `command-not-found-order46b.po.patch` | `command-not-found_23.04.0-3+sparky2.txt` |
| `kdeconnect` | `26.04.3-2+stereo3d1+lc1` | `+stereo3d3` incorporates the planned `+stereo3d2` catalogues and ORDER 924 | `kdeconnect-order46b.po.patch` | `kdeconnect_26.04.3-2+stereo3d3.txt` |
| `kf6-kfilemetadata` | `6.30.0-1+stereo3d5+lc1` | `successor to 6.30.0-1+stereo3d5+lc1` | `kf6-kfilemetadata-order46b.po.patch` | `kf6-kfilemetadata_6.30.0-1+stereo3d6.txt` |
| `kf6-kio` | `6.30.0-1+stereo3d11+lc1` | `successor to 6.30.0-1+stereo3d11+lc1` | `kf6-kio-order46b.po.patch` | `kf6-kio_6.30.0-1+stereo3d12.txt` |
| `kinfocenter` | `4:6.7.4-1+stereo3d3+lc1` | `successor to 4:6.7.4-1+stereo3d3+lc1` | `kinfocenter-order46b.patch` | `kinfocenter_6.7.4-1+stereo3d4.txt` |
| `krdc` | `4:26.04.0-1+stereo3d1+lc1` | `successor to 4:26.04.0-1+stereo3d1+lc1` | `krdc-order46b.po.patch` | `krdc_26.04.0-1+stereo3d2.txt` |
| `krdp` | `6.7.4-1+stereo3d11` | `+stereo3d11 packaging and series` | `krdp-order46b.packaging.patch, krdp-order46b.patch` | — |
| `kscreenlocker` | `6.7.4-1+stereo3d3+lc1` | `6.7.4-1+stereo3d4+lc1 staged and installed` | `kscreenlocker-edition-l10n.po.patch` | `kscreenlocker_6.7.4-1+stereo3d4.txt` |
| `kwin` | `4:6.7.4-2+stereo3d62+lc1` | `+stereo3d62 recipe, after existing series` | `kwin-order46b.patch` | — |
| `plasma-desktop` | `4:6.7.4-1+stereo3d4+lc1` | `successor to 4:6.7.4-1+stereo3d4+lc1` | `plasma-desktop-order46b.po.patch` | `plasma-desktop_6.7.4-1+stereo3d5.txt` |
| `plasma-discover` | `6.7.4-3+stereo3d2+lc1` | `successor to 6.7.4-3+stereo3d2+lc1` | `plasma-discover-order46b.po.patch` | `plasma-discover_6.7.4-3+stereo3d3.txt` |
| `plasma-nm` | `4:6.7.4-2+stereo3d1+lc1` | `successor to 4:6.7.4-2+stereo3d1+lc1` | `plasma-nm-order46b.po.patch` | `plasma-nm_6.7.4-2+stereo3d2.txt` |
| `plasma-stereo-wallpaper` | `0.1.1-1+lc1` | `successor to 0.1.1-1+lc1` | `plasma-stereo-wallpaper-order46b.patch` | `plasma-stereo-wallpaper_0.1.1-2.txt` |
| `plasma-workspace` | `4:6.7.4-2+stereo3d10+lc1` | `successor to 4:6.7.4-2+stereo3d10+lc1` | `plasma-workspace-order46b.po.patch` | `plasma-workspace_6.7.4-2+stereo3d11.txt` |
| `powerdevil` | `4:6.7.4-1+stereo3d2+lc1` | `successor to 4:6.7.4-1+stereo3d2+lc1` | `powerdevil-order46b.po.patch` | `powerdevil_6.7.4-1+stereo3d3.txt` |
| `sparky-stereo-browser` | `6.7.5-0+stereo3d15+lc1` | `6.7.5-0+stereo3d15+lc1 packaging, then the next browser build` | `sparky-stereo-browser-order46b.packaging.patch` | — |
