#!/bin/sh
# usage (as QMLBIN under td.py): runtest.sh <app.qml> -- <test binary> [slots...]
shift 2
exec "$@"
