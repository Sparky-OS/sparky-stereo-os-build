# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Per-file work on every processor this process may use, results in the order given (ORDER 638).

Workers are forks: they never import the caller's main module again (a recipe's build.py calls the toolkit at its top)
and they keep what this process primed. Each starts its own checker processes, since the pipes of the ones it inherited
are this process's, and at its end removes what it started, never a tool this process built.
"""
import concurrent.futures
import multiprocessing
import multiprocessing.util
import os
from pathlib import Path

from . import lang_js, lang_jvm, lang_rust, lang_shell, lang_zig


def processors():
    """The processors the scheduler lets this process use, no more than its cgroup's CPU quota grants."""
    count = len(os.sched_getaffinity(0))
    try:
        quota, period = Path('/sys/fs/cgroup/cpu.max').read_text().split()
        if quota != 'max':
            count = min(count, -(-int(quota) // int(period)))
    except (OSError, ValueError):
        pass
    return max(count, 1)


def _end(inherited):
    lang_jvm._close()
    for module, temporary in inherited.items():
        if module._temporary is not temporary:
            module._close()


def _worker():
    lang_js._node = lang_shell._bash = lang_jvm._process = lang_jvm._temporary = None
    multiprocessing.util.Finalize(None, _end, args=({module: module._temporary for module in (lang_rust, lang_zig)},),
                                  exitpriority=0)


def ordered(function, items):
    """function(item) for each item, in the items' order; with one processor, in this process."""
    items = list(items)
    workers = min(processors(), len(items))
    if workers < 2:
        yield from map(function, items)
        return
    pool = concurrent.futures.ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context('fork'),
                                                  initializer=_worker)
    try:
        yield from pool.map(function, items, chunksize=max(1, len(items) // (workers * 16)))
    finally:
        pool.shutdown(cancel_futures=True)
