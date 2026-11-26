// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>

// The cameras of the session as PipeWire sees them (Video/Source nodes), and the session's default video source,
// which WirePlumber keeps (metadata "default": default.configured.video.source is the person's choice and is saved
// by WirePlumber across restarts, default.video.source is the node every program that asks PipeWire gets).
namespace Sparky::Camera
{
struct CameraNode {
    int id = 0;
    qint64 serial = 0; // object.serial: unique for the session's life, so a camera plugged in again is a new node even with a reused id
    QString name; // node.name: the stable name WirePlumber stores
    QString description;
    QString v4l2Path; // /dev/videoN when the node is a V4L2 device
    QString api; // v4l2, libcamera or other
    QString state;
    bool isDefault = false; // WirePlumber's current default.video.source
    bool isConfigured = false; // the person's choice (default.configured.video.source)
};

struct NodeList {
    QList<CameraNode> cameras;
    QString error; // empty when PipeWire answered
};

NodeList listCameraNodes();
// Sets default.configured.video.source; WirePlumber saves it and moves default.video.source. Empty string on success.
QString setDefaultCamera(const QString &nodeName);
}
