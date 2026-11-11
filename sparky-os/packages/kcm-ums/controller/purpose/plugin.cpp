// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include <KLocalizedString>
#include <KPluginFactory>
#include <Purpose/Job>
#include <Purpose/PluginBase>
#include <QJsonArray>
#include <QMimeDatabase>
#include <QProcess>
#include <QStandardPaths>

class SendJob : public Purpose::Job
{
    Q_OBJECT
public:
    using Purpose::Job::Job;
    void start() override
    {
        const auto urls = data().value(QStringLiteral("urls")).toArray();
        const QUrl url(urls.size() == 1 ? urls.first().toString() : QString());
        const auto mime = QMimeDatabase().mimeTypeForUrl(url).name();
        if (urls.size() != 1 || !url.isLocalFile()
            || !(mime.startsWith(QLatin1String("video/")) || mime.startsWith(QLatin1String("audio/")) || mime.startsWith(QLatin1String("image/")))) {
            setError(KJob::UserDefinedError);
            setErrorText(i18nd("kcm_ums", "Choose one local media file."));
        } else {
            const auto executable = QStandardPaths::findExecutable(QStringLiteral("ums-renderer"));
            if (executable.isEmpty()
                || !QProcess::startDetached(executable, {QStringLiteral("--target"), QStringLiteral(UMS_TARGET), QStringLiteral("--"), url.toString()})) {
                setError(KJob::UserDefinedError);
                setErrorText(i18nd("kcm_ums", "Media Devices could not start."));
            }
        }
        emitResult();
    }
};
class SendPlugin : public Purpose::PluginBase
{
    Q_OBJECT
public:
    using Purpose::PluginBase::PluginBase;
    Purpose::Job *createJob() const override
    {
        return new SendJob;
    }
};
#ifdef UMS_HEADSET
K_PLUGIN_CLASS_WITH_JSON(SendPlugin, "headset.json")
#else
K_PLUGIN_CLASS_WITH_JSON(SendPlugin, "tv.json")
#endif
#include "plugin.moc"
