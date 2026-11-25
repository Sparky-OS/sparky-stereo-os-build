#!/usr/bin/env python3
# verdicts.py RESULTS [--lag-max N] -- the rows of row 863's stereo-widget-move test, one per case: expected against got.
# memcheck-MODE: no error context that reads a freed QPlatformTextureList, the run ended by itself (rc 0, a result
# line), every step placed. lag-MODE: the run ended by itself and every step placed; the top level's commits that
# carried the stereo window elsewhere than its widget are reported (and judged only with --lag-max). Exit 1 when a row
# is not as expected.
import json
import re
import sys
from pathlib import Path


def result(case):
    text = (case / 'result.txt').read_text(errors='replace') if (case / 'result.txt').exists() else ''
    rc = re.search(r'rc=(\d+)', text)
    res = re.search(r'R863 result mode=(\S+) steps=(\d+) stereo=(\d) native=(\d) stale=(\d+)', text)
    return text, (int(rc.group(1)) if rc else None), res


def texture_list_contexts(memcheck):
    # one context per error block whose stack or free stack names QPlatformTextureList
    blocks, cur = [], []
    for line in memcheck.read_text(errors='replace').splitlines():
        body = re.sub(r'^==\d+==\s?', '', line)
        if not body.strip():
            if cur:
                blocks.append(cur)
                cur = []
            continue
        cur.append(body)
    if cur:
        blocks.append(cur)
    errors = [b for b in blocks if re.match(r'(Invalid (read|write)|Use of|Mismatched|Conditional|Syscall)', b[0])]
    tl = [b for b in errors if any('QPlatformTextureList' in l for l in b)]
    summary = re.search(r'ERROR SUMMARY: (\d+) errors from (\d+) contexts', memcheck.read_text(errors='replace'))
    return len(tl), len(errors), (summary.group(0) if summary else 'no summary')


def main():
    results = Path(sys.argv[1])
    lag_max = None
    if '--lag-max' in sys.argv:
        lag_max = int(sys.argv[sys.argv.index('--lag-max') + 1])
    ok = True
    for case in sorted(p for p in results.iterdir() if p.is_dir() and p.name != 'bin'):
        text, rc, res = result(case)
        ended = rc == 0 and res is not None
        stale = int(res.group(5)) if res else None
        stereo = res.group(3) == '1' and res.group(4) == '1' if res else False
        if case.name.startswith('memcheck-'):
            mc = case / 'memcheck.txt'
            n_tl, n_err, summary = texture_list_contexts(mc) if mc.exists() else (None, None, 'no log')
            good = ended and stereo and stale == 0 and n_tl == 0
            got = f'ended={ended} stereo window={stereo} stale steps={stale} texture-list error blocks={n_tl} of {n_err}; {summary}'
            want = 'ended, stereo window, 0 stale steps, 0 texture-list error blocks'
        else:
            lag = json.loads((case / 'lag.json').read_text()) if (case / 'lag.json').exists() else {}
            good = ended and stereo and stale == 0 and 'commits' in lag
            if lag_max is not None and lag.get('misplaced_shown', 1 << 30) > lag_max:
                good = False
            got = (f"ended={ended} stereo window={stereo} stale steps={stale}; commits={lag.get('commits')} "
                   f"misplaced={lag.get('misplaced')} misplaced on screen={lag.get('misplaced_shown')} of shown={lag.get('shown_commits')} "
                   f"longest run={lag.get('longest_run')} ms to place={lag.get('ms_to_place')}")
            want = 'ended, stereo window, 0 stale steps' + (f', at most {lag_max} misplaced on screen' if lag_max is not None else '; misplaced commits measured')
        print(f"{'PASS' if good else 'FAIL'} {case.name}: expected {want}; got {got}")
        ok = ok and good
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
