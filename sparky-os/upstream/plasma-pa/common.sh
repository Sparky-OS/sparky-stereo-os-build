#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Host-side inputs shared by the source and binary producers.
IMAGE=${IMAGE:-debian@sha256:cf15c569a84dfda832e421ab27a8049e962ba8e90571612396cd8db799279e4e}
CPUS=${CPUS:-2}
BUILD_UID=$(id -u)
BUILD_GID=$(id -g)
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull --platform linux/amd64 "$IMAGE"
fi
