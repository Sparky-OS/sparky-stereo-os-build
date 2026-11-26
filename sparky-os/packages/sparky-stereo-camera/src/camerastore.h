// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "v4l2camera.h"

#include <QMap>
#include <QString>

// What the person chose for each camera, kept in ~/.config/sparky-stereo-camera/cameras.ini (an INI file any program
// can read), under the camera's key: the V4L2 bus_info and card name, so the choice follows the camera to the same
// port after it is unplugged. The default camera is not here: WirePlumber keeps it.
namespace Sparky::Camera
{
// 2 (0.1.3): only settings are kept (keepRule), and a control is taken from the camera only while it is active. An entry without
// it was written by 0.1.0 to 0.1.2, which saved every control whose reading differed from its default; the apply step cleans
// such an entry once, with the camera present, and marks it 2.
constexpr int StoreVersion = 2;

struct CameraChoice {
    bool exists = false; // the file has an entry for this camera
    int version = 1; // StoreVersion of the program that wrote the entry; 1 when the entry has no version
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
