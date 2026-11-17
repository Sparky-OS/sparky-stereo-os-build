// SPDX-License-Identifier: GPL-2.0-or-later
#include "depth-interface.h"
namespace Depth {
Limits desktopLimits() { return {}; }
int parallax(qreal, int) { return 0; }
int eyeShift(int, bool) { return 0; }
int authoredDisparity(qreal, Limits, int) { return 0; }
}
