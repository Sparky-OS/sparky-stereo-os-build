// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "tell.h"
#include "logging.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KNotification>
#include <KSharedConfig>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <sparky-stereo-problems.h>

namespace Throw
{

namespace
{
const char Package[] = "sparky-stereo-throw";

QString translated(const QString &context, const QString &message, const QStringList &args)
{
    const QByteArray c = context.toUtf8();
    const QByteArray m = message.toUtf8();
    KLocalizedString text = ki18nc(c.constData(), m.constData());
    for (const auto &arg : args) {
        text = text.subs(arg);
    }
    return text.toString();
}

void keep(const QString &key, const QString &message, const QStringList &args, const QString &severity, const QString &english)
{
    QList<QByteArray> bytes;
    std::vector<const char *> argv;
    for (const auto &arg : args) {
        bytes.append(arg.toUtf8());
    }
    for (const auto &b : bytes) {
        argv.push_back(b.constData());
    }
    const QJsonObject details{{QStringLiteral("severity"), severity}, {QStringLiteral("text_en"), english}};
    const QByteArray json = QJsonDocument(details).toJson(QJsonDocument::Compact);
    if (ssp_keep(SSP_PERSON, Package, key.toUtf8().constData(), message.toUtf8().constData(), argv.data(), int(argv.size()), json.constData()) != 0) {
        qCWarning(THROW) << "the problems engine did not keep" << key << ":" << ssp_error_en();
    }
}
} // namespace

void Tell::event(const QString &event, const QString &text)
{
    qCInfo(THROW) << "notice" << event << text;
    auto notification = new KNotification(event, KNotification::CloseOnTimeout);
    notification->setComponentName(QStringLiteral("sparkystereothrow"));
    notification->setText(text);
    notification->sendEvent();
}

void Tell::failure(const QString &deviceId, const QString &context, const QString &message, const QStringList &args, const QString &english)
{
    qCWarning(THROW) << "failed:" << english;
    // the engine renders CONTEXT|MSGID from the package's gettext catalogue in the person's language
    keep(QStringLiteral("throw:") + deviceId, context + QLatin1Char('|') + message, args, QStringLiteral("failed"), english);
    event(QStringLiteral("throwFailed"), translated(context, message, args));
}

void Tell::clear(const QString &deviceId)
{
    ssp_clear(SSP_PERSON, Package, (QStringLiteral("throw:") + deviceId).toUtf8().constData());
}

void Tell::unknownModel(const QString &deviceId, const QString &name, const QString &model)
{
    KConfigGroup group = KSharedConfig::openConfig(QStringLiteral("sparky-stereo-throwrc"))->group(QStringLiteral("Device")).group(deviceId);
    if (group.readEntry("ToldUnknownModel", false)) {
        return;
    }
    const QString context = QStringLiteral("@info a Cast device whose model is not in the table; %1 its name, %2 its model");
    const QString message = QStringLiteral(
        "%1 (model %2) is not in the device table. Its Throw uses the limits of the first Chromecast: 1920x1080 at 30 frames a second, H.264.");
    keep(QStringLiteral("unknown-model:") + deviceId, context + QLatin1Char('|') + message, {name, model}, QStringLiteral("notice"),
         QString(message).arg(name, model));
    event(QStringLiteral("unknownModel"), translated(context, message, {name, model}));
    group.writeEntry("ToldUnknownModel", true);
    group.sync();
}

} // namespace Throw
