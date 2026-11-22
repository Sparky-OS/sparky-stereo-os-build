/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
#pragma once

#include <QString>
#include <QStringList>

namespace SparkyStereo {

enum class OutputKind { Stream = 0, Record = 1, Replay = 2 };

// What the next start of one output will carry on a stereo canvas: the encoder, whether its stream holds the frame
// packing arrangement message, and a sentence for each mark it will not hold, with the reason.
struct MarkPlan {
	QString encoderId;
	bool streamMarked = false;
	QStringList missing;
};

// Hands the edition's libobs the main canvas's layout: full side by side, left eye first, on a stereo canvas, 2D otherwise.
// The encoders and muxers of the edition's OBS read it when they start and write the 3D marks from it.
// Returns true when the layout changed. With atReset the layout is taken by the next video reset, in the same step as the
// canvas size it is set for (OBS_STEREO3D_FLAG_AT_RESET), and true is returned: the caller resets the video.
bool setCanvasLayout(bool stereo, bool atReset = false);

// The plan for the next start of kind, from the encoder the output already has or, before its first start, the one
// the profile names (Settings, Output).
MarkPlan planFor(OutputKind kind);

// Reads the first video keyframe of the output kind while it runs and says in OBS's log what it carries; on a stereo
// canvas a keyframe without the message is told to the person.
void watchOutput(OutputKind kind);
void unwatchOutput(OutputKind kind);

// Defined by the plugin: tells the person once a session, in OBS's window, and always in OBS's log.
void tell(const QString &sentence);

} // namespace SparkyStereo
