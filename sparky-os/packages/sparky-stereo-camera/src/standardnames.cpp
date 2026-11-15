// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "standardnames.h"

#include <KLocalizedString>

#include <linux/videodev2.h>

using namespace Sparky::Camera;

// The context of each entry is the kernel constant it is tied to, so a translator sees which control it is.
QString Sparky::Camera::controlLabel(quint32 id, const QString &driverName)
{
    switch (id) {
    case V4L2_CID_BRIGHTNESS:
        return i18nc("V4L2_CID_BRIGHTNESS", "Brightness");
    case V4L2_CID_CONTRAST:
        return i18nc("V4L2_CID_CONTRAST", "Contrast");
    case V4L2_CID_SATURATION:
        return i18nc("V4L2_CID_SATURATION", "Saturation");
    case V4L2_CID_HUE:
        return i18nc("V4L2_CID_HUE", "Hue");
    case V4L2_CID_AUTO_WHITE_BALANCE:
        return i18nc("V4L2_CID_AUTO_WHITE_BALANCE", "White Balance, Automatic");
    case V4L2_CID_GAMMA:
        return i18nc("V4L2_CID_GAMMA", "Gamma");
    case V4L2_CID_GAIN:
        return i18nc("V4L2_CID_GAIN", "Gain");
    case V4L2_CID_POWER_LINE_FREQUENCY:
        return i18nc("V4L2_CID_POWER_LINE_FREQUENCY", "Power Line Frequency");
    case V4L2_CID_SHARPNESS:
        return i18nc("V4L2_CID_SHARPNESS", "Sharpness");
    case V4L2_CID_BACKLIGHT_COMPENSATION:
        return i18nc("V4L2_CID_BACKLIGHT_COMPENSATION", "Backlight Compensation");
    case V4L2_CID_WHITE_BALANCE_TEMPERATURE:
        return i18nc("V4L2_CID_WHITE_BALANCE_TEMPERATURE", "White Balance Temperature");
    case V4L2_CID_HFLIP:
        return i18nc("V4L2_CID_HFLIP", "Horizontal Flip");
    case V4L2_CID_VFLIP:
        return i18nc("V4L2_CID_VFLIP", "Vertical Flip");
    case V4L2_CID_EXPOSURE_AUTO:
        return i18nc("V4L2_CID_EXPOSURE_AUTO", "Auto Exposure");
    case V4L2_CID_EXPOSURE_ABSOLUTE:
        return i18nc("V4L2_CID_EXPOSURE_ABSOLUTE", "Exposure Time, Absolute");
    case V4L2_CID_EXPOSURE_AUTO_PRIORITY:
        return i18nc("V4L2_CID_EXPOSURE_AUTO_PRIORITY", "Exposure, Dynamic Framerate");
    case V4L2_CID_FOCUS_ABSOLUTE:
        return i18nc("V4L2_CID_FOCUS_ABSOLUTE", "Focus, Absolute");
    case V4L2_CID_FOCUS_AUTO:
        return i18nc("V4L2_CID_FOCUS_AUTO", "Focus, Automatic Continuous");
    case V4L2_CID_ZOOM_ABSOLUTE:
        return i18nc("V4L2_CID_ZOOM_ABSOLUTE", "Zoom, Absolute");
    case V4L2_CID_PAN_ABSOLUTE:
        return i18nc("V4L2_CID_PAN_ABSOLUTE", "Pan, Absolute");
    case V4L2_CID_TILT_ABSOLUTE:
        return i18nc("V4L2_CID_TILT_ABSOLUTE", "Tilt, Absolute");
    default:
        return driverName;
    }
}

QString Sparky::Camera::menuLabel(quint32 controlId, qint64 index, const QString &driverText)
{
    if (controlId == V4L2_CID_POWER_LINE_FREQUENCY) {
        switch (index) {
        case V4L2_CID_POWER_LINE_FREQUENCY_DISABLED:
            return i18nc("V4L2_CID_POWER_LINE_FREQUENCY_DISABLED", "Disabled");
        case V4L2_CID_POWER_LINE_FREQUENCY_50HZ:
            return i18nc("V4L2_CID_POWER_LINE_FREQUENCY_50HZ", "50 Hz");
        case V4L2_CID_POWER_LINE_FREQUENCY_60HZ:
            return i18nc("V4L2_CID_POWER_LINE_FREQUENCY_60HZ", "60 Hz");
        case V4L2_CID_POWER_LINE_FREQUENCY_AUTO:
            return i18nc("V4L2_CID_POWER_LINE_FREQUENCY_AUTO", "Auto");
        }
    } else if (controlId == V4L2_CID_EXPOSURE_AUTO) {
        switch (index) {
        case V4L2_EXPOSURE_AUTO:
            return i18nc("V4L2_EXPOSURE_AUTO", "Auto Mode");
        case V4L2_EXPOSURE_MANUAL:
            return i18nc("V4L2_EXPOSURE_MANUAL", "Manual Mode");
        case V4L2_EXPOSURE_SHUTTER_PRIORITY:
            return i18nc("V4L2_EXPOSURE_SHUTTER_PRIORITY", "Shutter Priority Mode");
        case V4L2_EXPOSURE_APERTURE_PRIORITY:
            return i18nc("V4L2_EXPOSURE_APERTURE_PRIORITY", "Aperture Priority Mode");
        }
    }
    return driverText;
}

QString Sparky::Camera::formatLabel(const QString &fourcc, const QString &driverText)
{
    // The codec and sampling names (YUYV 4:2:2, Motion-JPEG, H.264) are identifiers and stay as the kernel writes them
    if (fourcc == QLatin1String("GREY")) {
        return i18nc("V4L2_PIX_FMT_GREY", "8-bit Greyscale");
    }
    if (fourcc == QLatin1String("Y16 ")) {
        return i18nc("V4L2_PIX_FMT_Y16", "16-bit Greyscale");
    }
    return driverText;
}
