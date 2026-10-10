// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "memoryhelper.h"
#include "memorysettings.h"

#include <KAuth/HelperSupport>

#include <QProcess>

using namespace Qt::StringLiterals;

KAuth::ActionReply MemoryHelper::save(const QVariantMap &args)
{
    const QString zram = args.value(u"zram"_s).toString();
    const QString cushion = args.value(u"cushion"_s).toString();
    if (!QStringList{u"auto"_s, u"on"_s, u"off"_s}.contains(zram) || !QStringList{u"on"_s, u"off"_s}.contains(cushion)) {
        KAuth::ActionReply reply = KAuth::ActionReply::HelperErrorReply();
        reply.setErrorDescription(u"Invalid value"_s);
        return reply;
    }

    QString error;
    if (!MemorySettings::writeValue(MemorySettings::zramConfigPath(), u"ZRAM"_s, zram, &error)) {
        KAuth::ActionReply reply = KAuth::ActionReply::HelperErrorReply();
        reply.setErrorDescription(error);
        return reply;
    }
    const QString previous = MemorySettings::readValue(MemorySettings::cushionConfigPath(), u"CUSHION_SWAP"_s);
    if (!MemorySettings::writeValue(MemorySettings::cushionConfigPath(), u"CUSHION_SWAP"_s, cushion, &error)) {
        KAuth::ActionReply reply = KAuth::ActionReply::HelperErrorReply();
        reply.setErrorDescription(error);
        return reply;
    }

    KAuth::ActionReply reply = KAuth::ActionReply::SuccessReply();
    // The daemon reads its setting at start; switching it off never switches the swap off.
    if ((previous == u"off"_s) != (cushion == u"off"_s)) {
        reply.addData(u"restart"_s, QProcess::execute(u"systemctl"_s, {u"restart"_s, u"cushion-swap.service"_s}));
    }
    return reply;
}

KAUTH_HELPER_MAIN("org.sparkylinux.sparkystereo.memory", MemoryHelper)

#include "moc_memoryhelper.cpp"
