// SPDX-License-Identifier: GPL-2.0-or-later
#include "depth-interface.h"
#include "desktop-depth.h"
#include <KConfig>
#include <KConfigGroup>
#include <QStandardPaths>
#include <cmath>
#include <stdexcept>
namespace Depth {
Limits desktopLimits()
{
    KConfig config(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/kwinrc", KConfig::SimpleConfig);
    KConfigGroup group(&config, "StereoDepth");
    Limits limits{group.readEntry("SunkLimit", DesktopGeometry::StereoSunkLimit), group.readEntry("PoppedLimit", DesktopGeometry::StereoPoppedLimit)};
    return limits;
}
Limits defaultLimits() { return {DesktopGeometry::StereoSunkLimit, DesktopGeometry::StereoPoppedLimit}; }
int referenceWidth() { return int(DesktopGeometry::s_referenceWidth); }
int parallax(qreal reference, int width) { return DesktopGeometry::StereoDepth::parallax(reference, width); }
int eyeShift(int disparity, bool right)
{
    return DesktopGeometry::StereoDepth::eyeShift(disparity, right ? DesktopGeometry::StereoEye::Right : DesktopGeometry::StereoEye::Left);
}
int authoredDisparity(qreal value, Limits limits, int width)
{
    if (!value) return 0; // The screen plane is exact, including when the desktop disables depth.
    const qreal limit = value < 0 ? limits.sunk : limits.popped;
    const int capacity = std::abs(parallax(limit, width)); // Width is the OUTPUT's width in screen pixels, never the icon canvas.
    if (!capacity) return 0;
    const int requested = std::abs(parallax(value * limit, width));
    // One raster pixel is the smallest visible step. Never enlarge the full-limit budget.
    return (value < 0 ? -1 : 1) * qBound(1, requested, capacity);
}
}
