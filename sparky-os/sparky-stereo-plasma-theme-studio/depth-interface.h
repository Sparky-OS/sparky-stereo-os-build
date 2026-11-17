// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QtGlobal>
namespace Depth {
struct Limits { qreal sunk = 0; qreal popped = 0; };
Limits desktopLimits();
Limits defaultLimits();
int referenceWidth();
int parallax(qreal reference, int width);
int eyeShift(int disparity, bool right);
int authoredDisparity(qreal value, Limits limits, int width);
}
