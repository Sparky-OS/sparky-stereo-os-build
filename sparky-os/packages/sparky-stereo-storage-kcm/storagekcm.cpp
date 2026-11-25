// SPDX-License-Identifier: GPL-3.0-or-later
#include "storagekcm.h"

#include <KFormat>
#include <KLocalizedString>
#include <KPluginFactory>
#include <QDir>
#include <QDateTime>
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

// Some BleachBit definitions use the internal ID as their label and
// provide the human-readable, translated text as their description.
static void useDisplayDescription(QVariantMap &entry)
{
    const auto label = entry.value(u"label"_s).toString();
    const auto description = entry.value(u"description"_s).toString();
    if (label == entry.value(u"id"_s).toString() && !description.isEmpty()) {
        entry.insert(u"label"_s, description);
        entry.remove(u"description"_s);
    }
}

static QVariantList displayCatalogue(const QJsonArray &catalogue)
{
    auto groups = catalogue.toVariantList();
    for (auto &entry : groups) {
        auto group = entry.toMap();
        useDisplayDescription(group);
        auto options = group.value(u"options"_s).toList();
        for (auto &choice : options) {
            auto option = choice.toMap();
            useDisplayDescription(option);
            choice = option;
        }
        group.insert(u"options"_s, options);
        entry = group;
    }
    return groups;
}

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
    QTimer::singleShot(0, this, &StorageKcm::loadSchedule);
    auto *refresh = new QTimer(this);
    refresh->setInterval(15000);
    connect(refresh, &QTimer::timeout, this, &StorageKcm::loadSchedule);
    refresh->start();
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
        if (m_openPreview == u"admin-preview"_s && !m_admin) {
            chooseAdministrator(true);
            return;
        }
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
    m_previewed = false;
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
    m_previewed = false;
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
    m_previewed = false;
    m_cleaners.clear();
    catalogue();
    loadSchedule();
}

void StorageKcm::catalogue()
{
    runBleachBit({u"--json"_s, u"--list-cleaners"_s}, u"cleaners"_s);
}

void StorageKcm::setOption(const QString &cleaner, const QString &option, bool value)
{
    m_items.clear();
    m_previewed = false;
    runBleachBit({u"--json"_s, u"--set-option"_s, cleaner + u'.' + option,
                  value ? u"true"_s : u"false"_s}, u"cleaners"_s);
}

QStringList StorageKcm::selectedOperations() const
{
    if (!m_cachesOnly || m_admin) {
        return {u"--preset"_s};
    }

    QStringList operations;
    for (const auto &group : m_cleaners) {
        const auto cleaner = group.toMap();
        const QString id = cleaner.value(u"id"_s).toString();
        if (id != u"firefox"_s && id != u"thunderbird"_s && id != u"evolution"_s && id != u"waterfox"_s) {
            continue;
        }
        for (const auto &choice : cleaner.value(u"options"_s).toList()) {
            const auto option = choice.toMap();
            if (option.value(u"id"_s) == u"cache"_s && option.value(u"checked"_s).toBool()) {
                operations << id + u".cache"_s;
            }
        }
    }
    return operations;
}

QVariantMap StorageKcm::describeItem(QVariantMap item) const
{
    const auto operation = item.value(u"operation"_s).toString();
    const auto separator = operation.indexOf(u'.');
    const auto cleanerId = operation.isEmpty() ? item.value(u"cleaner"_s).toString() : operation.section(u'.', 0, 0);
    const auto optionId = separator < 0 ? item.value(u"option"_s).toString() : operation.mid(separator + 1);
    for (const auto &entry : m_cleaners) {
        const auto cleaner = entry.toMap();
        if (cleaner.value(u"id"_s).toString() != cleanerId) {
            continue;
        }
        item.insert(u"cleanerLabel"_s, cleaner.value(u"label"_s));
        for (const auto &choice : cleaner.value(u"options"_s).toList()) {
            const auto option = choice.toMap();
            if (option.value(u"id"_s).toString() == optionId) {
                item.insert(u"optionLabel"_s, option.value(u"label"_s));
                item.insert(u"description"_s, option.value(u"description"_s));
                item.insert(u"warning"_s, option.value(u"warning"_s));
                break;
            }
        }
        break;
    }
    return item;
}

void StorageKcm::preview()
{
    const QStringList args{u"--json"_s, u"--preview"_s, u"--volume"_s, m_volume};
    const QStringList age{u"--temporary-age-days"_s, QString::number(temporaryAge())};
    runBleachBit(args + selectedOperations() + age, u"items"_s);
}

void StorageKcm::clean(const QStringList &approved)
{
    if (approved.isEmpty() || m_readOnly) {
        return;
    }
    const QByteArray input = QJsonDocument(QJsonArray::fromStringList(approved)).toJson(QJsonDocument::Compact);
    const QStringList args{u"--json"_s, u"--clean"_s, u"--volume"_s, m_volume};
    const QStringList confirm{u"--approved-stdin"_s, u"--temporary-age-days"_s, QString::number(temporaryAge())};
    runBleachBit(args + selectedOperations() + confirm, u"clean"_s, input);
}

void StorageKcm::loadSchedule()
{
    auto *job = new QProcess(this);
    const bool system = m_admin;
    connect(job, &QProcess::finished, this, [this, job, system](int status) {
        if (system == m_admin) {
            const auto result = QJsonDocument::fromJson(job->readAllStandardOutput()).object();
            if (status == 0 && result.contains("settings"_L1)) {
                const auto settings = result.value("settings"_L1).toObject();
                m_period = settings.value("period"_L1).toString();
                m_scheduledAction = settings.value("action"_L1).toString();
                m_runs.clear();
                for (const auto &entry : result.value("runs"_L1).toArray()) {
                    auto run = entry.toObject().toVariantMap();
                    const auto date = QDateTime::fromSecsSinceEpoch(run.value(u"at"_s).toLongLong());
                    run.insert(u"date"_s, QLocale().toString(date, QLocale::ShortFormat));
                    m_runs.append(run);
                }
            } else {
                m_errors = {QVariantMap{{u"reason"_s, i18n("Could not read the cleanup schedule.")}}};
            }
            Q_EMIT changed();
        }
        job->deleteLater();
    });
    connect(job, &QProcess::errorOccurred, this, [this, job](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_errors = {QVariantMap{{u"reason"_s, i18n("Could not read the cleanup schedule.")}}};
            Q_EMIT changed();
            job->deleteLater();
        }
    });
    job->start(u"/usr/libexec/sparky-storage-cleanup-schedule"_s,
               {system ? u"show-system"_s : u"show"_s});
}

void StorageKcm::setSchedule(const QString &period, const QString &action)
{
    if (m_busy) {
        return;
    }
    auto *job = new QProcess(this);
    m_busy = true;
    const auto finish = [this, job](int status) {
        m_busy = false;
        if (status != 0) {
            m_errors = {QVariantMap{{u"reason"_s, i18n("Could not save the schedule.") + u' ' +
                                                   QString::fromUtf8(job->readAllStandardError()).trimmed()}}};
        } else {
            m_errors.clear();
        }
        loadSchedule();
        Q_EMIT changed();
        job->deleteLater();
    };
    connect(job, &QProcess::finished, this, finish);
    connect(job, &QProcess::errorOccurred, this, [finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(-1);
        }
    });
    if (m_admin) {
        const auto language = KLocalizedString::languages().join(u':');
        job->start(u"/usr/bin/pkexec"_s, {u"/usr/libexec/sparky-storage-cleanup-admin"_s,
                                         language, u"schedule-set"_s, period, action, m_volume});
    } else {
        job->start(u"/usr/libexec/sparky-storage-cleanup-schedule"_s, {u"set"_s, period, action, m_volume});
    }
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
            m_cleaners = displayCatalogue(result.value("cleaners"_L1).toArray());
        } else if (startedVolume == m_volume) {
            m_readOnly = result.value("read_only"_L1).toBool();
            m_errors.clear();
            for (const auto &error : result.value("errors"_L1).toArray()) {
                m_errors.append(describeItem(error.toObject().toVariantMap()));
            }
            if (field == u"items"_s) {
                m_items.clear();
                m_previewed = true;
                for (const auto &candidate : result.value("items"_L1).toArray()) {
                    m_items.append(describeItem(candidate.toObject().toVariantMap()));
                }
            } else {
                m_items.clear();
                m_previewed = true;
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
