// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "camerastore.h"
#include "pipewirecameras.h"
#include "v4l2camera.h"

#include <QJsonArray>
#include <QSet>
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
// The camera of that node name. PipeWire's list is the graph at the moment pw-dump asked (it binds every object and syncs before
// printing), and a camera that is being plugged in, or whose node is being made again, is missing from it for a moment: the list is
// asked again until the name is there or waitMs has passed, and only then is "No camera called NAME is present." said.
CameraInfo findCamera(const QString &nodeName, QString *error, int waitMs = 3000);

// What happened when the saved choice was applied to a camera
struct ApplyReport {
    QStringList messages; // one sentence for each thing the camera refused (translated; each is also kept by the problems engine)
    QStringList log; // what was done that is not a failure, for the journal: a setting left while inactive, an entry cleaned, the best mode
    int applied = 0;
    bool reached = false; // the camera's device opened and answered: false asks the unit to try again at its next pass
    bool ok() const { return messages.isEmpty(); }
};
// Applies the camera's saved choice: the controls that change the picture's layout (V4L2_CTRL_FLAG_MODIFY_LAYOUT), the saved mode
// or, when none is saved, the best mode (bestModeFor), then the other saved controls with V4l2Camera::setControls. A saved setting
// still inactive at the end keeps its value for when it is active, and no problem. An entry 0.1.0 to 0.1.2 wrote is cleaned once.
ApplyReport applyChoice(const CameraInfo &camera);

// After the person changed a governing control (automatic white balance off): a saved value of a control that was inactive before
// (wasInactive) and is active now waited for this, and is set on the camera before anything is saved. Returns journal lines.
QStringList applyWaiting(V4l2Camera &device, const CameraChoice &stored, const QSet<quint32> &wasInactive);

// The choice to save from the camera's present state: settings only (keepRule), each one taken from the camera only while it is
// active and not held by another program; such a setting keeps the value a 0.1.3 entry held for it. The mode is the camera's
// present mode when withMode, else the stored one (a mode the person did not choose is not saved).
CameraChoice choiceFromDevice(V4l2Camera &device, const CameraChoice &stored, bool withMode);

// The best mode of a camera (bestMode) with the known machine's caveat for this camera, and the note when the caveat leaves none
struct BestModeChoice {
    std::optional<Mode> mode;
    QStringList allowedFormats; // the caveat's formats; empty: every format
    QString note; // for the journal when no mode could be chosen
};
BestModeChoice bestModeFor(V4l2Camera &device);

// The USB vendor:product of a V4L2 device ("0bda:5722"), from sysfs; empty for a camera that is not on USB
QString usbIdOf(const QString &v4l2Path);
// The references of the known machines that match this computer (sparky-stereo-hardware's table, sparky-stereo-known-machines --list)
QJsonArray knownMachineReferences();
// A camera caveat in that table: a reference with "owner": "sparky-stereo-camera", "camera": "VVVV:PPPP" and "formats": [...] names
// the only formats in which that camera, in that machine, delivers a correct picture. Empty: no caveat for this camera.
QStringList machineFormatsFor(const QJsonArray &references, const QString &usbId);
// The known machines' references that concern a camera, in words
QStringList knownMachineNotes();
}
