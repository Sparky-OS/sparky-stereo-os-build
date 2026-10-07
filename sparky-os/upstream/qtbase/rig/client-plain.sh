#!/bin/bash
export QT_STEREO_HOLD_MS=${QT_STEREO_HOLD_MS:-20000}
exec /usr/local/bin/qt-plain
