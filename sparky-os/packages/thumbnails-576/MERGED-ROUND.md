# Two staged works on one library

`merged-round.sh WORK FORK REV PUBLISHED ARCHIVE STAGE_551 STAGE_551B DOLPHIN_SOURCE`
builds the layer from the exact revision once, then rebuilds Dolphin from its accepted source descriptor.
For ORDER 580 the revision is stereo-layer main 6bb9fb9, version 1.19.1-1+lc1.
It contains both the album menu of 1.19.0 and the device-pixel fix of 1.18.1.
There is no source change to the layer or to Dolphin.

The older rounds remain independently reproducible.
The merged round copies their other staged packages, excluding their layer and Dolphin, into its dependency repository.
The link gate's previous side is the published tree; its candidate side excludes every replaced source from the published siblings.
Compare the resulting library exports separately against both staged predecessors.
Install the combined set and qualify the dependants before deciding which need rebuilding.

`DOLPHIN_SOURCE` is the accepted Dolphin +stereo3d8 source folder.
Its descriptor and tarballs are copied without rewriting a date or bundling a different toolkit.
Reusing that binary version requires confirming it was never published.
`SPARKY_BUILD_IMAGE` optionally names a local tag of the migration image; its actual image ID is recorded.
The generic depth-source recipe uses explicit bind mounts, so an absent input fails rather than becoming an empty directory.

The round checks disk space before each source generation and binary build.
Resource monitoring during a build remains the caller's responsibility.
