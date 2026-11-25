// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// Saying what happened: a running Throw's own events through KNotification, and every failure kept in the edition's
// problems engine (libsparky-stereo-problems) until a Throw to that device works again.
#pragma once

#include <QString>
#include <QStringList>

namespace Throw
{

namespace Tell
{
// a notice of a running Throw (event of sparkystereothrow.notifyrc)
void event(const QString &event, const QString &text);
// a failure for this device: kept under the key throw:<device id> with the message in the person's language
void failure(const QString &deviceId, const QString &context, const QString &message, const QStringList &args, const QString &english);
// the device works again
void clear(const QString &deviceId);
// a device whose model is not in the table, said once per device (kept as a notice)
void unknownModel(const QString &deviceId, const QString &name, const QString &model);
} // namespace Tell

} // namespace Throw
