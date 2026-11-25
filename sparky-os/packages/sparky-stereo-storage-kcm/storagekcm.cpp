// SPDX-License-Identifier: GPL-3.0-or-later
#include "storagekcm.h"

#include <KFormat>
#include <KLocalizedString>
#include <KPluginFactory>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTimer>
#include <utility>

using namespace Qt::StringLiterals;

static QString configPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + u"/sparky-storage-cleanuprc"_s;
}

StorageKcm::StorageKcm(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : KQuickConfigModule(parent, data)
{
    setButtons(NoAdditionalButton);
    connect(this, &KAbstractConfigModule::activationRequested, this, &StorageKcm::activate);
    activate(args);
    QTimer::singleShot(0, this, &StorageKcm::catalogue);
}

void StorageKcm::activate(const QVariantList &args)
{
    if (args.isEmpty()) {
        return;
    }
    const auto activation = args.constFirst().toString().split(u':');
    const auto url = QByteArray::fromBase64(activation.constFirst().toLatin1(), QByteArray::Base64UrlEncoding);
    const QString path = QString::fromUtf8(url);
    chooseVolume(path);
    if (m_volume == path && activation.size() == 2) {
        m_openPreview = activation.last();
        if (!m_busy && !m_cleaners.isEmpty()) {
            m_cachesOnly = m_openPreview == u"caches"_s;
            m_openPreview.clear();
            preview();
        }
    }
}

QVariantList StorageKcm::volumes() const
{
    QVariantList result;
    bool hasActiveVolume = false;
    for (const auto &volume : QStorageInfo::mountedVolumes()) {
        if (volume.isValid() && volume.isReady() && volume.bytesTotal() > 0
            && !volume.rootPath().startsWith(u"/proc/"_s) && !volume.rootPath().startsWith(u"/sys/"_s)) {
            hasActiveVolume |= volume.rootPath() == m_volume;
            result.append(QVariantMap{{u"path"_s, volume.rootPath()},
                                      {u"label"_s, volume.rootPath() == u"/"_s ? i18n("System volume") : volume.rootPath()}});
        }
    }
    if (!hasActiveVolume) {
        result.append(QVariantMap{{u"path"_s, m_volume}, {u"label"_s, m_volume}});
    }
    return result;
}

int StorageKcm::schedule() const
{
    return QSettings(configPath(), QSettings::IniFormat).value(u"scheduleMode"_s, 2).toInt();
}

QString StorageKcm::formatSize(qint64 bytes) const
{
    return KFormat().formatByteSize(bytes);
}

int StorageKcm::temporaryAge() const
{
    return QSettings(configPath(), QSettings::IniFormat).value(u"temporaryAge"_s, 7).toInt();
}

void StorageKcm::setTemporaryAge(int days)
{
    QSettings settings(configPath(), QSettings::IniFormat);
    settings.setValue(u"temporaryAge"_s, days);
    settings.sync();
    m_items.clear();
    if (settings.status() != QSettings::NoError) {
        m_errors = {QVariantMap{{u"reason"_s, i18n("Could not save the minimum age.")}}};
    }
    Q_EMIT changed();
}

void StorageKcm::chooseVolume(const QString &path)
{
    const QStorageInfo volume(path);
    if (!volume.isValid() || !volume.isReady() || volume.rootPath() != QDir::cleanPath(path)) {
        return;
    }
    m_volume = volume.rootPath();
    m_cachesOnly = false;
    m_readOnly = volume.isReadOnly();
    m_items.clear();
    m_errors.clear();
    Q_EMIT changed();
}

void StorageKcm::chooseAdministrator(bool admin)
{
    if (m_busy || m_admin == admin) {
        return;
    }
    m_admin = admin;
    m_items.clear();
    m_cleaners.clear();
    catalogue();
}

void StorageKcm::catalogue()
{
    runBleachBit({u"--json"_s, u"--list-cleaners"_s}, u"cleaners"_s);
}

void StorageKcm::setOption(const QString &cleaner, const QString &option, bool value)
{
    m_items.clear();
    runBleachBit({u"--json"_s, u"--set-option"_s, cleaner + u'.' + option,
                  value ? u"true"_s : u"false"_s}, u"cleaners"_s);
}

void StorageKcm::preview()
{
    QStringList args{u"--json"_s, u"--preview"_s, u"--volume"_s, m_volume};
    if (m_cachesOnly && !m_admin) {
        for (const auto &group : std::as_const(m_cleaners)) {
            const QVariantMap cleaner = group.toMap();
            const QString id = cleaner.value(u"id"_s).toString();
            if (id == u"firefox"_s || id == u"thunderbird"_s || id == u"evolution"_s || id == u"waterfox"_s) {
                for (const auto &option : cleaner.value(u"options"_s).toList()) {
                    const QVariantMap item = option.toMap();
                    if (item.value(u"id"_s).toString() == u"cache"_s && item.value(u"checked"_s).toBool()) {
                        args << id + u".cache"_s;
                    }
                }
            }
        }
    } else {
        args << u"--preset"_s;
    }
    args << u"--temporary-age-days"_s << QString::number(temporaryAge());
    runBleachBit(args, u"items"_s);
}

void StorageKcm::clean(const QStringList &approved)
{
    if (approved.isEmpty() || m_readOnly) {
        return;
    }
    const QByteArray input = QJsonDocument(QJsonArray::fromStringList(approved)).toJson(QJsonDocument::Compact);
    runBleachBit({u"--json"_s, u"--clean"_s, u"--volume"_s, m_volume, u"--preset"_s,
                  u"--approved-stdin"_s, u"--temporary-age-days"_s, QString::number(temporaryAge())}, u"clean"_s, input);
}

void StorageKcm::setSchedule(int mode)
{
    if (mode < 0 || mode > 3 || mode == schedule() || m_busy) {
        return;
    }
    QSettings settings(configPath(), QSettings::IniFormat);
    const auto beforeMode = settings.value(u"scheduleMode"_s);
    const auto beforeMount = settings.value(u"scheduleMount"_s);
    settings.setValue(u"scheduleMode"_s, mode);
    settings.setValue(u"scheduleMount"_s, m_volume);
    settings.sync();
    if (settings.status() != QSettings::NoError) {
        m_errors = {QVariantMap{{u"reason"_s, i18n("Could not save the schedule.")}}};
        Q_EMIT changed();
        return;
    }
    auto *job = new QProcess(this);
    m_busy = true;
    const bool weekly = mode == 1 || mode == 3;
    const auto finish = [this, job, beforeMode, beforeMount](int status) {
        m_busy = false;
        if (status != 0) {
            QSettings restore(configPath(), QSettings::IniFormat);
            for (const auto &[key, value] : {std::pair{u"scheduleMode"_s, beforeMode},
                                             std::pair{u"scheduleMount"_s, beforeMount}}) {
                if (value.isValid()) {
                    restore.setValue(key, value);
                } else {
                    restore.remove(key);
                }
            }
            restore.sync();
            m_errors = {QVariantMap{{u"reason"_s, i18n("Could not save the schedule.") + u' ' +
                                                   QString::fromUtf8(job->readAllStandardError()).trimmed()}}};
        }
        Q_EMIT changed();
        job->deleteLater();
    };
    connect(job, &QProcess::finished, this, finish);
    connect(job, &QProcess::errorOccurred, this, [finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(-1);
        }
    });
    job->start(u"/usr/bin/systemctl"_s,
               {u"--user"_s, weekly ? u"enable"_s : u"disable"_s, u"--now"_s, u"sparky-storage-cleanup.timer"_s});
    Q_EMIT changed();
}

void StorageKcm::runBleachBit(const QStringList &args, const QString &field, const QByteArray &input)
{
    if (m_busy) {
        return;
    }
    auto *job = new QProcess(this);
    m_errors.clear();
    m_busy = true;
    const QString startedVolume = m_volume;
    connect(job, &QProcess::started, this, [job, input] {
        job->write(input);
        job->closeWriteChannel();
    });
    const auto failed = [this, job] {
        m_errors = {QVariantMap{{u"reason"_s, i18n("Could not run BleachBit.") + u' ' + job->errorString()}}};
        m_busy = false;
        Q_EMIT changed();
        job->deleteLater();
    };
    connect(job, &QProcess::errorOccurred, this, [failed](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            failed();
        }
    });
    connect(job, &QProcess::finished, this, [this, job, field, startedVolume](int status) {
        m_busy = false;
        const auto document = QJsonDocument::fromJson(job->readAllStandardOutput());
        const auto result = document.object();
        if (result.value("schema"_L1).toInt() != 1 || result.contains("error"_L1)) {
            auto reason = result.value("error"_L1).toString();
            if (reason.isEmpty()) {
                reason = QString::fromUtf8(job->readAllStandardError()).trimmed();
            }
            if (reason.isEmpty()) {
                reason = i18n("Could not run BleachBit.");
            }
            m_errors = {QVariantMap{{u"reason"_s, reason}}};
        } else if (field == u"cleaners"_s) {
            m_cleaners = result.value("cleaners"_L1).toArray().toVariantList();
        } else if (startedVolume == m_volume) {
            m_readOnly = result.value("read_only"_L1).toBool();
            m_errors = result.value("errors"_L1).toArray().toVariantList();
            if (field == u"items"_s) {
                m_items.clear();
                for (const auto &candidate : result.value("items"_L1).toArray()) {
                    auto row = candidate.toObject().toVariantMap();
                    for (const auto &group : std::as_const(m_cleaners)) {
                        const auto cleaner = group.toMap();
                        if (cleaner.value(u"id"_s) != row.value(u"cleaner"_s)) {
                            continue;
                        }
                        for (const auto &choice : cleaner.value(u"options"_s).toList()) {
                            const auto option = choice.toMap();
                            if (option.value(u"id"_s) == row.value(u"option"_s)) {
                                row.insert(u"description"_s, option.value(u"description"_s));
                                row.insert(u"warning"_s, option.value(u"warning"_s));
                                break;
                            }
                        }
                        break;
                    }
                    m_items.append(row);
                }
            } else {
                m_items.clear();
                const auto cleaned = result.value("items"_L1).toArray().size();
                m_errors.prepend(QVariantMap{{u"reason"_s, i18n("Items cleaned: %1", cleaned)}});
            }
        }
        if (status && m_errors.isEmpty()) {
            m_errors = {QVariantMap{{u"reason"_s, i18n("Could not run BleachBit.")}}};
        }
        Q_EMIT changed();
        job->deleteLater();
        if (field == u"cleaners"_s && !m_openPreview.isEmpty() && !m_cleaners.isEmpty()) {
            m_cachesOnly = m_openPreview == u"caches"_s;
            m_openPreview.clear();
            preview();
        }
    });
    if (m_admin) {
        auto environment = QProcessEnvironment::systemEnvironment();
        const QString languages = environment.value(u"LANGUAGE"_s, QLocale().name());
        job->start(u"/usr/bin/pkexec"_s,
                   QStringList{u"--disable-internal-agent"_s, u"/usr/libexec/sparky-storage-cleanup-admin"_s, languages} + args);
    } else {
        job->start(u"/usr/bin/bleachbit"_s, args);
    }
    Q_EMIT changed();
}

K_PLUGIN_CLASS_WITH_JSON(StorageKcm, "kcm_sparkystereo_storage_cleanup.json")
#include "storagekcm.moc"
