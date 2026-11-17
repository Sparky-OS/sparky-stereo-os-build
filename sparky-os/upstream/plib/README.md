# plib per-draw stereo cameras

The source producer starts from the published plib 1.8.5-15+stereo3d2+lc1 descriptor, checks its hash and retains Debian's complete recipe.
It adds per-draw convergence, separation and an infinite-background path while preserving existing entry points and PLIB_SSG_CONVERGENCE / PLIB_SSG_EYE_SEPARATION overrides.

`build.sh PUBLISHED.dsc WORK POOL IMAGE ARCHIVE [EXTRA_DEBS]` prepares the source once, builds amd64 in a container and runs the current Lean Code, link and start gates.
POOL is the signed edition repository tree; IMAGE is an amd64 build image; ARCHIVE contains sources.json and its explicit public keyrings, as lean/archive.md describes.
WORK must be a fresh scratch directory.
The source's date comes from the recipe commit or an explicit SOURCE_DATE_EPOCH for an immutable prepared release.
No simulator or package is installed on the host.

The independent matrix oracle checks 5,000 points, caller-state restoration and zero vertical disparity, with a stereo-off negative.
The TORCS recipe exercises both finite scene and infinite background draws.
