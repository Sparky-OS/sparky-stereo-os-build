# Excluded base packages and living Debian sources

`rootfs.sh` checks every `lists/base-gone.tsv` row before creating a base tree, and again before a separately resumed packages step.
The check belongs here because this build consumes the exclusions; binary candidate checks alone cannot reveal a source that survives only in unstable.
It prints the binary, its historical source, unstable and Forky source presence, the unstable version, and a classification.
`SID-ONLY-REVIEW` calls attention to sources that need investigation even when the binary still has no testing candidate.
A source in testing can be a renamed binary or a retired transition package; this report never declares that the old binary is installable.

`check-base-gone-sources.py` reads the public Debian Sources API over HTTPS.
It queries each distinct source once with four workers, without adding sid binary sources to the image.
Unknown responses, network failures and excluded binaries without source mappings fail the build; they never become a claim that a source is absent.
The historical binary/source mapping lives in `lists/base-gone-sources.tsv`; the explicit `-` entries are the external Liquorix archive keys.
Published packages lose their exclusion rows; the historical mappings may remain.
Existing `base-list.sh` still checks actual candidates against the image's sources and pins.

Run `python3 iso-build/check-base-gone-sources.py --save /path/outside-the-source-tree/sources.json` from `sparky-os` to save an audit.
`--snapshot FILE` replays that response set for review without network access.
Run `python3 iso-build/test-base-gone-sources.py` in an isolated container for the source-return and failure controls.
A removal reason must be read again if a source returns: Debian's reintroduction of apt-xapian-index after its 2025 removal is one such case.
