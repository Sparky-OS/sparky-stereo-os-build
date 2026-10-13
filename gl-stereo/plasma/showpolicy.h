// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once


namespace StereoShow
{
struct Policy {
    bool enabled = true;
    int startSeconds = 135 * 60;
    int cycleSeconds = 10 * 60;

    bool visible(bool onAC, bool displayOn, bool locked, int idleSeconds, bool inhibited) const
    {
        return enabled && onAC && displayOn && (locked || (!inhibited && idleSeconds >= startSeconds));
    }
};
}
