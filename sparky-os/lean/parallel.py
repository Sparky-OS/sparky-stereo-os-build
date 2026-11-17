# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Per-file work on every processor this process may use, results in the order given (ORDER 638).

Workers start as fresh interpreters, so each starts its own checker processes, as a run of its own would.
"""
import concurrent.futures
import multiprocessing
import os
from pathlib import Path


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


def ordered(function, items, initializer=None, initargs=()):
    """function(item) for each item, in the items' order; with one processor, in this process."""
    items = list(items)
    workers = min(processors(), len(items))
    if workers < 2:
        yield from map(function, items)
        return
    pool = concurrent.futures.ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context('spawn'),
                                                  initializer=initializer, initargs=initargs)
    try:
        yield from pool.map(function, items, chunksize=max(1, len(items) // (workers * 16)))
    finally:
        pool.shutdown(cancel_futures=True)
