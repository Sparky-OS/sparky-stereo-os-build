# A picture set to "Not 3D" gets a flat thumbnail (ORDER 581)

kio-extras 4:26.04.0-1+stereo3d6+lc1, from the published +stereo3d5+lc1.

A marked picture (a PNG with an sTER chunk) that the person has set to "Not 3D" in the shared per-file store (ORDER 512) kept a pair thumbnail in Dolphin (found by ORDER 551c).
The stereo layer answered "not a pair" for it, correctly.
The image thumbnailer then read the file plainly, the edition's Qt put the file's own mark on that image as the text `Stereo3DLayout`, and the thumbnail worker sent any such text to the job as `stereo3dLayout`, which cached it as `X-KDE::Stereo3DLayout`: the flat read was announced as a pair.

Design followed (Daniel's words, as recorded):
- Never touch the user's file (2026-10-23) and the shared per-file store (ORDER 512): "A stored packing applies over the file's mark (a declaration can be wrong); with no entry the mark decides." A file set to "Not 3D" is flat everywhere, its thumbnail included, and the file is never written.
- Full side by side at any resolution (2026-10-22): a pair's thumbnail is a declared pair, each eye whole; a flat file's thumbnail is one picture.
- Nothing fails silently (2026-11-01): the thumbnail is made flat, not shown as a pair.
- Search upstream first (2026-11-01): upstream kio-extras has no stereo code; the lines touched are the edition's own (stereo-thumbnails.patch).

## Files

- `patches/kio-extras-plain-image-is-not-a-pair.patch`: `ImageCreator::create()` clears `Stereo3DLayout` on the plain read, after the layer's `loadPair()` has declined it.
  The JPEG thumbnailer needs no change: it reads with `QImageReader(path, "jpeg")`, the plain JPEG reader, which reports no such text (measured, `evidence/thumbcreate-published.txt`).
  The lead of ORDER 551c proposed a hunk there too; it is unreachable and left out.
- `changelog/kio-extras.items`: the changelog item.
- `next-source.sh PUBLISHED.dsc OUT`: the next +lc1 source (`repo/lc-successor.py --in-place --overlay`): the published history stays a byte identical suffix of the new changelog, and nothing else of debian/ changes but the patch, the series and the toolkit.
- `round.sh WORK PUBLISHED_TREE ARCHIVE_DIR`: the build through `../depth-source/build.sh` (Lean Code, the link and start gate, `lean.release check-debs`).

## Cached thumbnails

A thumbnail made by +stereo3d5 for a file already set to "Not 3D" holds the pair key and stays in the cache until the file's choice changes (`Picture::setFileChoice()` removes the file's cached thumbnails) or the thumbnailer's version goes up.
This package does not change `ThumbnailerVersion`: how the cache refreshes has no recorded design, and the measure is in the lane's report.

## Dependencies added or changed

None. Build-Depends and Depends are those of +stereo3d5 (`libstereo-layer-dev (>= 1.18.0)`, `libstereo-layer1 (>= 1.18.0)`).
