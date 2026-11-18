// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "headsetengine.h"

#include <QVariantMap>

// The person's choices, one group per headset in ~/.config/sparky-stereo-headsetrc (KConfig): only what the person changed is
// written, so a headset keeps every setting that was never touched here, and the choices come back when the same headset is plugged in again.
namespace Sparky::Headset
{
QVariantMap savedChoices(const QString &id);
void saveChoice(const QString &id, const QString &key, const QVariant &value);
void forgetChoices(const QString &id);

// One headset described for the page and the panel entry: only the settings it reports, each with its saved value
QVariantMap describe(const Headset &headset, const QVariantMap &saved);
QString batteryText(const Headset &headset);
}
