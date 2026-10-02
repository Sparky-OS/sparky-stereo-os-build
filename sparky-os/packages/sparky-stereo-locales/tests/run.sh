#!/bin/bash
# Run the round 1 tests, each in a fresh container from the base image.
# Usage: tests/run.sh path/to/package.deb [test ...]   (image: locales-r1-base, see tests/Dockerfile)
HERE=$(cd "$(dirname "$0")" && pwd)
DEB=$(readlink -f "$1"); shift
TESTS=("$@")
[ ${#TESTS[@]} -gt 0 ] || TESTS=(t1_kept_not_removed t1_refuse_extras t1_dryrun_exact t2_locale_codes t2_sr_latin t2_unknown_code t2_bare_keep t2_english_always t3_no_options t4_gui t5_path_excludes t5_path_excludes_keep_sr t6_strings t6_tree t7_restore)
RC=0
for t in "${TESTS[@]}"; do
	docker run --rm --cpus 4 -v "$HERE/..:$HERE/..:ro" -v "$(dirname "$DEB"):$(dirname "$DEB"):ro" \
		-e DEB="$DEB" -e TREE="$(cd "$HERE/.." && pwd)" locales-r1-base \
		bash "$HERE/round1.sh" "$t" 2>&1 || RC=1
done
exit $RC
