# ffmpeg-dmo +stereo3d15: stereo marks from hardware encoders

The complete 94-patch series preserves all 77 patches of +stereo3d14 and adds the encoder writer, side-data representations, regression tests and ORDER 174 integration.
The writer runs inside each encoder's existing metadata path.

VA-API uses `sei=frame_packing`, Vulkan uses `units=frame_packing`, and NVENC, QSV and AMF use the boolean `frame_packing`.
All default on.
Unsupported packings fail with a named diagnostic and an explicit marking opt-out.
AMF currently has no general SEI route and therefore refuses marked input.
HEVC requires clear non-packed constraints in both parameter sets, including applicable sublayers.
Plain 2D and explicitly disabled marking preserve the unpatched encoder's bytes.

The conversion and VA-API integration adapt Mark Thompson's [2019 helper](https://ffmpeg.org/pipermail/ffmpeg-devel/2019-October/250967.html) and [writer](https://ffmpeg.org/pipermail/ffmpeg-devel/2019-October/250966.html).
His co-authorship is retained.
The NVENC budget fix is upstream `96b7f8281a5f971ef1b061024d50b971c85d4a95`, by lusoris; it is a prerequisite already present in the master-based implementation but absent from +12.

## Building

Use the accepted +stereo3d14+lc1 source as the input.
Extract it with `dpkg-source --skip-patches`, then run `plain-from-lc.py --save-plan PLAN`.
Run `sparky-os/packages/ffmpeg-dmo/make-source-stereo3d15.py PLAIN14 ORIG OUT PLAN`.
The script adds this recipe's changelog entry, dated from its commit, and preserves the source plan.
Build both architectures from that one `.dsc` with `sparky-os/packages/ffmpeg-dmo/build.sh`.
The three deb-multimedia patches come from the input source; the recipe does not duplicate them.
Preparation makes carried patch headers name-only and retains their upstream Origin links.
The two Matroska eye-shape patches from +14 and their FATE reference stay unchanged.
No package dependency is added by this recipe.

## Port details

The writer was developed against FFmpeg master `b2b543c079241a63692245c26c743328385dfff6` and ported to the patched 9.0.2 tree.
The API bumps here are libavutil 61.2.100 for stereo layouts and 61.3.100 for the appended ORDER 174 fields.
The master-based stereo-layout commit uses 61.21.100.
The port preserves +12's decoder side-data preference handling; its mapping test calls the existing split frame-packing export function.
Makefile wiring uses the tests present in 9.0.2, without importing unrelated master tests.
NVENC retains 9.0.2's hardware-pixel-format condition.

All nine ORDER 174 changes are accounted for:

| Original commit | Integration |
|---|---|
| `343e881b80` | Base-layer probe counting, retaining +12's temporal-id validation |
| `5e3c14b4d1` | Raw alpha-stream probe test |
| `baa39b09ab` | Already present in patch 0030; preserve its additional splitting/depth handling |
| `af441af725` | AuxId/dependency-id regression test |
| `0a37c1d405` | Already present in patch 0025, including 64-bit CBS fields and split reads/writes |
| `ebf0c956e6` | CBS mantissa round-trip test |
| `1f79c14486` | Append full-width fields after +12's existing fields; populate both decoder routes |
| `15deb45a16` | Add raw reference-display fields to ffprobe, retaining the existing fields |
| `198dcf951a` | Frame mantissa test, selecting its original fields explicitly |

`h2645_sei_multiview.c` also populates the appended fields: +12 routes these messages through its shared H.264/HEVC metadata decoder.
The existing `AVMultiviewReal` fields remain available.
The encoder writer does not reuse the metadata-filter helper, and this recipe leaves that existing series intact.

The new CPU FATE targets are `fate-stereo3d`, `fate-h2645-stereo3d` and `fate-frame-packing`; the ORDER 174 targets are `fate-hevc-probe-layers`, `fate-hevc-alpha-dimension-id`, `fate-cbs-hevc-tdrdi-mantissa` and `fate-hevc-tdrdi-mantissa`.
Their external sample files must be supplied to `SAMPLES`, as for other FATE tests.
Hardware qualification requires the packing/order matrix and unpatched byte controls described in the public stereo-video skill; compilation alone does not qualify QSV or AMF runtimes.

The build driver runs sample-free GCC FATE on both architectures and retains the tree.
For the full suite, run `fate.sh BUILD OUT SAMPLES`; its log, exit status and target totals distinguish absent fixtures from passes.
The source plan preserves `libswscale/aarch64/ops_entries.c`, which FATE compares byte for byte with its generator output.
