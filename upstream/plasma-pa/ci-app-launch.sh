#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
prefix=$(cd "$(dirname "$(command -v plasmawindowed)")/.." && pwd)
# Archives retain their builders' absolute D-Bus Exec paths. Start the services
# at the actual test prefix, on Selenium's private bus, before opening the app.
# QT_FATAL_WARNINGS belongs to the tested app, not these background services.
env -u QT_FATAL_WARNINGS "$prefix/bin/kded6" > "$CI_PROJECT_DIR/pa19-kded.log" 2>&1 &
env -u QT_FATAL_WARNINGS "$prefix/lib64/libexec/kactivitymanagerd" > "$CI_PROJECT_DIR/pa19-activities.log" 2>&1 &
dbus-send --session --print-reply --dest=org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop org.freedesktop.DBus.Introspectable.Introspect \
    > "$CI_PROJECT_DIR/pa19-portal.log"
exec plasmawindowed -p org.kde.plasma.nano org.kde.plasma.volume
