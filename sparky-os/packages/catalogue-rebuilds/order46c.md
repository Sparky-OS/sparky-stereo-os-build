# ORDER 46 program catalogues

The receiver manifest names the published source and the successor for each
programme. The patches contain the edition's strings. Use the edition release
archives and verify the referenced source members against the signed index.

After extracting the matching LC source descriptor, run
`python3 prepare-order46c.py SOURCE_TREE` here. It checks the version and the patch
with fuzz disabled. It adds the patch at the end of the quilt series, or applies
it to a native source, and prepends the successor changelog entry. Build with
`dpkg-buildpackage` and the source's usual Lean Code gates. The catalogue-only
patches leave the program forks available for their upstream build and review
flows.

When receiving a newer edition source, compare the exact catalogue keys with
the target release before regenerating the patch. In particular, legacy Dragon
and VLC patch files have Git diff headers now. The successor patches take only
the needed translations on top of the already patched published source.
