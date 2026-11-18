#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run the unchanged release checks with one Python worker.

Native subprocesses retain the container's CPU quota. Only the toolkit's
worker-count provider is configured; validation, input selection, ordering,
exceptions and the release command's exit status remain authoritative.
"""
from contextlib import contextmanager
import sys

from lean import parallel, release


@contextmanager
def one_worker():
    original = parallel.processors
    parallel.processors = lambda: 1
    try:
        yield
    finally:
        parallel.processors = original


def main():
    with one_worker():
        return release.main()


if __name__ == '__main__':
    sys.exit(main())
