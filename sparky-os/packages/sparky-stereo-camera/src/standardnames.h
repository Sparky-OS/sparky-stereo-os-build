// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>

// The names a person reads for the controls, menu entries and pixel formats the kernel standardises (linux/videodev2.h,
// V4L2_CID_* and V4L2_PIX_FMT_*). The English source is the kernel's own description (drivers/media/v4l2-core/v4l2-ctrls-defs.c and
// v4l2-ioctl.c); anything outside the lists keeps the driver's words.
namespace Sparky::Camera
{
QString controlLabel(quint32 id, const QString &driverName);
QString menuLabel(quint32 controlId, qint64 index, const QString &driverText);
QString formatLabel(const QString &fourcc, const QString &driverText);
}
