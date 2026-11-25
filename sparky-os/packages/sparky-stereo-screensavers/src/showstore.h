// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QStringList>

/* What the page reads from the files that hold it: the show's own values
 * (stereoshowrc, which the page also writes) and, read only, Screen Locking's
 * and the desktop's (kscreenlockerrc, plasmashell's desktop file). */
struct ShowStore {
    static constexpr int IDLE = 8100, CYCLE = 600; // the show's own defaults (gl-stereo-show, stereoshow.kcfg)
    bool enabled = true;
    int idleSeconds = IDLE, cycleSeconds = CYCLE;
    QStringList disabled, flat;
    bool autolock = true;
    int lockMinutes = 5;
    QString lockKind;
    QStringList desktopKinds;

    static ShowStore read();
    /* Writes the show's five values, with KConfig's notify flag; nothing else of any file. */
    void writeShow() const;
};
