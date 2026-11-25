// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "colourvisionkcm.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QStandardPaths>
#include <QVariantMap>

K_PLUGIN_CLASS_WITH_JSON(ColourVisionKcm, "kcm_sparkystereo_colourvision.json")

namespace
{
const QString helperProgram()
{
    const QString overridden = qEnvironmentVariable("SPARKY_STEREO_COLOUR_VISION_HELPER");
    return overridden.isEmpty() ? QStringLiteral("sparky-stereo-colour-vision") : overridden;
}

QString kindName(const QString &kind)
{
    if (kind == QLatin1String("protan")) {
        return i18nc("@item colour vision kind, used inside a sentence", "protan colour vision");
    }
    if (kind == QLatin1String("deutan")) {
        return i18nc("@item colour vision kind, used inside a sentence", "deutan colour vision");
    }
    if (kind == QLatin1String("tritan")) {
        return i18nc("@item colour vision kind, used inside a sentence", "tritan colour vision");
    }
    if (kind == QLatin1String("mono")) {
        return i18nc("@item colour vision kind, used inside a sentence", "monochromacy");
    }
    return kind;
}

QString roleName(const QString &role)
{
    if (role == QLatin1String("negative")) {
        return i18nc("@item colour role", "error text");
    }
    if (role == QLatin1String("positive")) {
        return i18nc("@item colour role", "success text");
    }
    if (role == QLatin1String("neutral")) {
        return i18nc("@item colour role", "warning text");
    }
    if (role == QLatin1String("link")) {
        return i18nc("@item colour role", "links");
    }
    if (role == QLatin1String("visited")) {
        return i18nc("@item colour role", "visited links");
    }
    if (role == QLatin1String("text")) {
        return i18nc("@item colour role", "normal text");
    }
    if (role == QLatin1String("focus decoration")) {
        return i18nc("@item colour role", "the focus frame");
    }
    return role;
}

QString errorText(const QJsonObject &s)
{
    const QString code = s.value(QStringLiteral("error")).toString();
    if (code == QLatin1String("EACCES") || code == QLatin1String("EPERM")) {
        return i18nc("@info reason a file could not be written", "permission denied");
    }
    if (code == QLatin1String("EROFS")) {
        return i18nc("@info reason a file could not be written", "the disk is read-only");
    }
    if (code == QLatin1String("ENOSPC")) {
        return i18nc("@info reason a file could not be written", "the disk is full");
    }
    if (code == QLatin1String("missing-program")) {
        return i18nc("@info %1 is a program name", "%1 is not installed", s.value(QStringLiteral("program")).toString());
    }
    if (code == QLatin1String("program-failed")) {
        return i18nc("@info %1 is a program name, %2 its exit status", "%1 ended with status %2", s.value(QStringLiteral("program")).toString(),
                     s.value(QStringLiteral("status")).toInt());
    }
    if (code == QLatin1String("no-scheme")) {
        return i18nc("@info", "your colour scheme file was not found");
    }
    if (code == QLatin1String("read-back")) {
        return i18nc("@info", "the setting did not read back as it was written");
    }
    return code;
}

QVariantMap surfaceRow(const QJsonObject &s, const QString &kind)
{
    const QString id = s.value(QStringLiteral("id")).toString();
    const QString state = s.value(QStringLiteral("state")).toString();
    const QString path = s.value(QStringLiteral("path")).toString();
    QString text;
    QString icon = QStringLiteral("dialog-ok-apply");
    if (state == QLatin1String("failed")) {
        icon = QStringLiteral("dialog-error");
    } else if (state == QLatin1String("pending") || state == QLatin1String("kept")) {
        icon = QStringLiteral("dialog-information");
    } else if (state == QLatin1String("off")) {
        icon = QStringLiteral("dialog-cancel");
    }

    if (id == QLatin1String("kwin")) {
        if (state == QLatin1String("set")) {
            text = i18nc("@info", "Screen correction: on, for %1.", kindName(kind));
        } else if (state == QLatin1String("pending")) {
            text = i18nc("@info", "Screen correction: saved for %1; the compositor did not answer, so it starts at your next login.", kindName(kind));
        } else if (state == QLatin1String("off")) {
            text = i18nc("@info", "Screen correction: off.");
        } else {
            text = i18nc("@info %1 file, %2 reason", "Screen correction: not set. Could not write %1: %2.", path, errorText(s));
        }
    } else if (id == QLatin1String("scheme")) {
        const QString name = s.value(QStringLiteral("name")).toString();
        if (state == QLatin1String("set")) {
            const QJsonArray close = s.value(QStringLiteral("close")).toArray();
            if (!s.value(QStringLiteral("measured")).toBool(true)) {
                text = i18nc("@info %1 colour scheme name",
                             "Colours: %1. This colour scheme was not measured; its colours that carry meaning now take the colour-vision map's colours.",
                             name);
            } else if (!close.isEmpty()) {
                QStringList pairs;
                for (const QJsonValue &p : close) {
                    const QJsonArray pair = p.toArray();
                    pairs.append(i18nc("@item two colours that look alike", "%1 and %2", roleName(pair.at(0).toString()), roleName(pair.at(1).toString())));
                }
                text = i18nc("@info %1 colour scheme name, %2 list of colour pairs",
                             "Colours: %1. In this colour scheme some colours stay close for you: %2. Sparky Stereo Oxygen Dark keeps them apart.",
                             name,
                             pairs.join(QStringLiteral("; ")));
            } else {
                text = i18nc("@info %1 colour scheme name", "Colours: %1, which keeps the colours that carry meaning apart.", name);
            }
        } else if (state == QLatin1String("off")) {
            text = i18nc("@info", "Colours: your own colour scheme, as you had it.");
        } else {
            text = i18nc("@info %1 colour scheme name, %2 reason", "Colours: %1 not applied: %2.", name.isEmpty() ? path : name, errorText(s));
        }
    } else if (id == QLatin1String("konsole")) {
        if (state == QLatin1String("set")) {
            text = i18nc("@info", "Konsole: new windows and tabs use the colour-safe colours; your own profile is kept and lends them everything else.");
        } else if (state == QLatin1String("off")) {
            text = i18nc("@info", "Konsole: not changed.");
        } else {
            text = i18nc("@info %1 file, %2 reason", "Konsole: not set. Could not write %1: %2.", path, errorText(s));
        }
    } else if (id == QLatin1String("nano")) {
        if (state == QLatin1String("set")) {
            text = i18nc("@info %1 file", "nano: its selection and guide colours follow the terminal's colours (%1).", path);
        } else if (state == QLatin1String("kept")) {
            text = i18nc("@info %1 the person's file, %2 lines to add", "nano: not changed, because %1 is your own file and stays as you wrote it. To get the same colours, add these lines to it: %2",
                         path, s.value(QStringLiteral("lines")).toString());
        } else if (state == QLatin1String("off")) {
            text = i18nc("@info", "nano: not changed.");
        } else {
            text = i18nc("@info %1 file, %2 reason", "nano: not set. Could not write %1: %2.", path, errorText(s));
        }
    } else if (id == QLatin1String("console")) {
        if (state == QLatin1String("set")) {
            text = i18nc("@info", "Text console, outside the desktop: the colour-safe palette from your next login there.");
        } else if (state == QLatin1String("off")) {
            text = i18nc("@info", "Text console: not changed.");
        } else {
            text = i18nc("@info %1 file, %2 reason", "Text console: not set. Could not write %1: %2.", path, errorText(s));
        }
    }
    return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("state"), state}, {QStringLiteral("text"), text}, {QStringLiteral("icon"), icon}};
}
}

ColourVisionKcm::ColourVisionKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(Apply | Default);
    // KDE's Accessibility page writes the same kwinrc keys: show its change here without reopening the page
    m_reload.setSingleShot(true);
    m_reload.setInterval(300);
    connect(&m_reload, &QTimer::timeout, this, [this] {
        if (!needsSave()) {
            load();
        }
    });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reload, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reload, qOverload<>(&QTimer::start));
    watchConfig();
}

void ColourVisionKcm::watchConfig()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    const QString kwinrc = dir + QStringLiteral("/kwinrc");
    if (!m_watcher.directories().contains(dir)) {
        m_watcher.addPath(dir);
    }
    if (QFile::exists(kwinrc) && !m_watcher.files().contains(kwinrc)) {
        m_watcher.addPath(kwinrc); // a rename over the file drops the watch; the folder's change adds it again
    }
}

bool ColourVisionKcm::runHelper(const QStringList &arguments, QJsonObject *result)
{
    QProcess process;
    process.start(helperProgram(), arguments);
    if (!process.waitForFinished(60000)) {
        m_helperError = i18nc("@info %1 program", "%1 did not answer.", helperProgram());
        process.kill();
        return false;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(process.readAllStandardOutput());
    if (process.exitStatus() != QProcess::NormalExit || !doc.isObject()) {
        m_helperError = i18nc("@info %1 program, %2 its message", "%1 failed: %2", helperProgram(), QString::fromUtf8(process.readAllStandardError()).trimmed());
        return false;
    }
    m_helperError.clear();
    *result = doc.object();
    return true;
}

void ColourVisionKcm::takeStatus(const QJsonObject &status)
{
    m_savedKind = status.value(QStringLiteral("kind")).toString(QStringLiteral("none"));
    m_savedTerminals = status.value(QStringLiteral("terminals")).toBool();
    m_surfaces.clear();
    const QJsonArray surfaces = status.value(QStringLiteral("surfaces")).toArray();
    for (const QJsonValue &s : surfaces) {
        m_surfaces.append(surfaceRow(s.toObject(), m_savedKind));
    }
    if (m_kind != m_savedKind) {
        m_kind = m_savedKind;
        Q_EMIT kindChanged();
    }
    if (m_terminals != m_savedTerminals) {
        m_terminals = m_savedTerminals;
        Q_EMIT terminalsChanged();
    }
    Q_EMIT surfacesChanged();
    updateNeedsSave();
}

void ColourVisionKcm::load()
{
    QJsonObject status;
    if (!runHelper({QStringLiteral("status"), QStringLiteral("--json")}, &status)) {
        Q_EMIT surfacesChanged();
        return;
    }
    takeStatus(status);
    watchConfig();
}

void ColourVisionKcm::save()
{
    QJsonObject status;
    const QStringList arguments{QStringLiteral("set"), m_kind, m_terminals ? QStringLiteral("--terminals") : QStringLiteral("--no-terminals"),
                                QStringLiteral("--json")};
    if (!runHelper(arguments, &status)) {
        Q_EMIT surfacesChanged();
        return;
    }
    takeStatus(status);
    watchConfig();
}

void ColourVisionKcm::defaults()
{
    setKind(QStringLiteral("none"));
    setTerminals(false);
}

void ColourVisionKcm::setKind(const QString &kind)
{
    if (kind == m_kind) {
        return;
    }
    m_kind = kind;
    Q_EMIT kindChanged();
    updateNeedsSave();
}

void ColourVisionKcm::setTerminals(bool terminals)
{
    if (terminals == m_terminals) {
        return;
    }
    m_terminals = terminals;
    Q_EMIT terminalsChanged();
    updateNeedsSave();
}

void ColourVisionKcm::updateNeedsSave()
{
    setNeedsSave(m_kind != m_savedKind || m_terminals != m_savedTerminals);
    setRepresentsDefaults(m_kind == QLatin1String("none") && !m_terminals);
}

#include "colourvisionkcm.moc"
