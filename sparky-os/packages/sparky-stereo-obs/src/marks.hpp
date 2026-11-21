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

// The x264 option the module adds: frame packing arrangement type 3, side by side (H.264 V16 D.2.26, Table D-9);
// x264 writes content_interpretation_type 1, frame 0 the left view (Table D-10).
inline constexpr const char *kX264Token = "frame-packing=3";

// On a stereo canvas, adds kX264Token to the x264 options of every OBS x264 encoder of the main canvas that is not
// running; on a 2D canvas, takes out the token this module added and nothing else.
void applyX264Mark(bool stereo);

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
