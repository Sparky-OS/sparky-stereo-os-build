// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "camerastore.h"
#include "pipewirecameras.h"
#include "v4l2camera.h"

#include <QStringList>

namespace Sparky::Camera
{
// One camera as the page and the command show it: the PipeWire node, and what the V4L2 device tells when it opens
struct CameraInfo {
    CameraNode node;
    QString key; // the store's key; empty when the camera is not a V4L2 device that opened
    QString card;
    QString busInfo;
    int openError = 0; // errno when the V4L2 device did not open
    QString note; // a sentence for the person when something about this camera is missing (translated)
};

QList<CameraInfo> listCameras(QString *error);
CameraInfo findCamera(const QString &nodeName, QString *error);

// What happened when the saved choice was applied to a camera
struct ApplyReport {
    QStringList messages; // one sentence for each thing the camera refused
    int applied = 0;
    bool ok() const { return messages.isEmpty(); }
};
ApplyReport applyChoice(const CameraInfo &camera);
// The known machines' references that concern a camera (sparky-stereo-hardware's table), in words
QStringList knownMachineNotes();
}
