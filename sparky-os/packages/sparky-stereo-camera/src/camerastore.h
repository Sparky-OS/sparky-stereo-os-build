// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "v4l2camera.h"

#include <QMap>
#include <QString>

// What the person chose for each camera, kept in ~/.config/sparky-stereo-camera/cameras.conf (an INI file any program
// can read), under the camera's key: the V4L2 bus_info and card name, so the choice follows the camera to the same
// port after it is unplugged. The default camera is not here: WirePlumber keeps it.
namespace Sparky::Camera
{
struct CameraChoice {
    bool hasMode = false;
    Mode mode;
    QString packing; // the stereo layer's input id ("sideBySideLeftFirst"); empty = not 3D
    QMap<quint32, qint64> controls; // the control id -> the value to set at plug-in
    QMap<quint32, QString> controlNames; // for a person reading the file
};

QString cameraKey(const QString &busInfo, const QString &card);
CameraChoice loadChoice(const QString &key);
void saveChoice(const QString &key, const CameraChoice &choice);
void forgetChoice(const QString &key);
}
