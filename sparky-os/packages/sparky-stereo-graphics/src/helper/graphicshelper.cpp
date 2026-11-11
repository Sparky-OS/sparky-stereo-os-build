// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "graphicshelper.h"
#include "vramsettings.h"
#include <KAuth/HelperSupport>
KAuth::ActionReply GraphicsHelper::savevram(const QVariantMap &args)
{
    if (args.size() != 1 || args.value(QStringLiteral("enabled")).metaType() != QMetaType::fromType<bool>()) {
        auto reply = KAuth::ActionReply::HelperErrorReply();
        reply.setErrorDescription(QStringLiteral("Invalid boolean setting"));
        return reply;
    }
    QString error;
    if (!SparkyGraphics::VramSettings::writeEnabled(args.value(QStringLiteral("enabled")).toBool(), &error)) {
        auto reply = KAuth::ActionReply::HelperErrorReply();
        reply.setErrorDescription(error);
        return reply;
    }
    return KAuth::ActionReply::SuccessReply();
}
KAUTH_HELPER_MAIN("org.sparkylinux.sparkystereo.graphics", GraphicsHelper)
#include "moc_graphicshelper.cpp"
