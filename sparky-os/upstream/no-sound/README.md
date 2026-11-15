# A film without sound says so (ORDER 579)

The sentence "This film has no sound." and the rule (loaded, a picture, no audio track) are the stereo layer's (`NoSound`, stereo-layer 1.21.0).

| Program | How the next version is made | Patch |
|---|---|---|
| stereo-layer 1.21.0-1+lc1 | `mk-layer-source.sh` from stereo-layer main (3ee2dcc) | none, it is the layer |
| bino 2.8-1+stereo3d10+lc1 | `mk-successors.sh` (lc-successor --in-place --overlay) | patches/bino-0007 |
| haruna 1.8.1-1+stereo3d5+lc1 | `mk-successors.sh` | patches/haruna-0007 |
| dragonplayer 4:26.04.0-1+stereo3d12+lc1 | `mk-successors.sh` | patches/dragon-0014 |
| plank-player ...-1+stereo3d5+lc1 | `mk-successors.sh` | patches/plank-player-0007 |
| sview 26.9+stereo3d6+lc1 | `mk-sview-source.sh` from the sView fork commit 54469b1, the successor of 41bddfc6 (ORDER 529, +stereo3d5) | patches/sview-26.9+stereo3d6-from-stereo3d5.patch (for reading) |
| VLC Stereo | no package from this recipe | patches/vlc-3d-0050-... (a proposal for the VLC recipe, after 3d-0049 of +stereo3d20; not applied here) |

`build-in-container.sh` builds the binaries of a made source with `dpkg-buildpackage -b`, so the staged `.dsc` and tarballs stay the ones the source scripts made.
`tests/no-sound-wording/check.py` fails when the sView or VLC copy of the sentence differs from the layer's.
