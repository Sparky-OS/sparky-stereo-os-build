// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "signerstate.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KNotification>
#include <KSharedConfig>
#include <KStatusNotifierItem>

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QMenu>
#include <QMessageBox>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

// PJeOffice Pro vetoes its own tray on Unix (PjeOfficeFrontEnd.supportsSystray rejects Unix platforms), so this is the tray entry
// of the edition: a KStatusNotifierItem that shows whether the signer answers on localhost and offers the few things a person
// needs from it. It never claims that a token or a court is authenticated: it only knows that the signer answers.
class Tray : public QObject
{
    Q_OBJECT
public:
    Tray()
        : m_item(QStringLiteral("sparky-pjeoffice"), nullptr)
    {
        m_item.setTitle(i18n("PJeOffice Pro"));
        m_item.setCategory(KStatusNotifierItem::ApplicationStatus);
        m_item.setIconByName(QStringLiteral("application-certificate"));
        m_item.setAttentionIconByName(QStringLiteral("dialog-warning"));
        m_item.setStandardActionsEnabled(false);
        m_item.setStatus(KStatusNotifierItem::Passive);

        auto *menu = new QMenu();
        m_version = menu->addAction(QString());
        m_version->setEnabled(false);
        m_health = menu->addAction(QString());
        m_health->setEnabled(false);
        menu->addSeparator();
        m_open = menu->addAction(i18n("Open the signer"), this, &Tray::openSigner);
        m_restart = menu->addAction(i18n("Restart the signer"), this, &Tray::restartSigner);
        menu->addAction(i18n("Check CNJ's update address"), this, &Tray::checkUpstream);
        menu->addAction(i18n("Settings…"), this, &Tray::openSettings);
        menu->addSeparator();
        menu->addAction(i18n("Quit this tray entry (the signer keeps running)"), qApp, &QApplication::quit);
        m_item.setContextMenu(menu);
        connect(&m_item, &KStatusNotifierItem::activateRequested, this, [this]() {
            openSigner();
        });

        connect(&m_state, &SignerState::probeFinished, this, &Tray::probed);
        m_timer.setInterval(10000);
        connect(&m_timer, &QTimer::timeout, &m_state, &SignerState::probe);
        m_timer.start();
        refresh();
        m_state.probe();
    }

    // At login, with "Start PJeOffice Pro when I log in" on (the default), the signer is started once; if the person closes it later,
    // nothing starts it again.
    void startSignerOnce()
    {
        KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("sparkystereopjeofficerc")), QStringLiteral("General"));
        if (group.readEntry("Autostart", true) && !SignerState::installedVersion().isEmpty()) {
            QProcess::startDetached(SignerState::launcher(), {});
        }
    }

private Q_SLOTS:
    void probed(bool answers)
    {
        if (m_hadAnswer && !answers && !m_stopSaid) {
            m_stopSaid = true;
            auto *note = new KNotification(QStringLiteral("signerStopped"));
            note->setComponentName(QStringLiteral("sparky-pjeoffice"));
            note->setTitle(i18n("PJeOffice Pro"));
            note->setText(i18n("The signer stopped answering."));
            note->sendEvent();
        }
        if (answers) {
            m_hadAnswer = true;
            m_stopSaid = false;
        }
        refresh();
    }

    void refresh()
    {
        const QString installed = SignerState::installedVersion();
        const bool answers = m_state.answers();
        const bool known = m_state.probed();
        m_version->setText(installed.isEmpty() ? i18n("PJeOffice Pro is not installed.") : i18n("Version %1", installed));
        const QString reviewed = SignerState::reviewedVersion();
        if (installed.isEmpty()) {
            m_health->setText(i18n("Install it from the app center."));
        } else if (!reviewed.isEmpty() && reviewed != installed) {
            m_health->setText(i18n("Reviewed version %1 is waiting; %2 is in use.", reviewed, installed));
        } else {
            m_health->setText(i18n("The installed version is the reviewed one."));
        }
        m_restart->setVisible(SignerState::restartPending() && answers);
        m_open->setEnabled(!installed.isEmpty());
        QString line;
        if (installed.isEmpty()) {
            line = i18n("PJeOffice Pro is not installed.");
            m_item.setStatus(KStatusNotifierItem::Passive);
        } else if (!known) {
            line = i18n("Looking for the signer…");
            m_item.setStatus(KStatusNotifierItem::Passive);
        } else if (answers) {
            line = SignerState::restartPending() ? i18n("The signer answers on this computer. The system's certificate list changed: restart the signer to use it.")
                                                  : i18n("The signer answers on this computer.");
            m_item.setStatus(KStatusNotifierItem::Active);
        } else {
            line = i18n("The signer does not answer on this computer. Open it from this menu.");
            m_item.setStatus(KStatusNotifierItem::NeedsAttention);
        }
        m_item.setToolTip(QStringLiteral("application-certificate"), i18n("PJeOffice Pro"), line);
    }

    void openSigner()
    {
        if (SignerState::installedVersion().isEmpty()) {
            return;
        }
        QProcess::startDetached(SignerState::launcher(), {});
        QTimer::singleShot(1500, &m_state, &SignerState::probe);
    }

    void restartSigner()
    {
        const auto answer = QMessageBox::question(nullptr, i18n("PJeOffice Pro"),
                                                   i18n("Restart the signer now? Finish any signing first: a signing in progress would be cut."));
        if (answer != QMessageBox::Yes) {
            return;
        }
        QFile pid(QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/sparky-pjeoffice/signer.pid"));
        if (pid.open(QIODevice::ReadOnly)) {
            const qint64 number = pid.readAll().trimmed().toLongLong();
            QFile cmd(QStringLiteral("/proc/%1/cmdline").arg(number));
            if (number > 1 && cmd.open(QIODevice::ReadOnly) && cmd.readAll().contains("PjeOfficePROUser")) {
                QProcess::execute(QStringLiteral("/usr/bin/kill"), {QString::number(number)});
            }
        }
        QTimer::singleShot(3000, this, &Tray::openSigner);
    }

    void checkUpstream()
    {
        auto *process = new QProcess(this);
        connect(process, &QProcess::finished, this, [this, process]() {
            auto *note = new KNotification(QStringLiteral("updateChecked"));
            note->setComponentName(QStringLiteral("sparky-pjeoffice"));
            note->setTitle(i18n("PJeOffice Pro"));
            note->setText(QString::fromUtf8(process->readAllStandardOutput()).trimmed() + QString::fromUtf8(process->readAllStandardError()).trimmed());
            note->sendEvent();
            process->deleteLater();
        });
        process->start(SignerState::command(), {QStringLiteral("check")});
    }

    void openSettings()
    {
        QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_sparkystereo_pjeoffice")});
    }

private:
    KStatusNotifierItem m_item;
    SignerState m_state;
    QTimer m_timer;
    QAction *m_version = nullptr;
    QAction *m_health = nullptr;
    QAction *m_open = nullptr;
    QAction *m_restart = nullptr;
    bool m_hadAnswer = false;
    bool m_stopSaid = false;
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sparky-pjeoffice-tray"));
    app.setDesktopFileName(QStringLiteral("sparky-pjeoffice"));
    app.setQuitOnLastWindowClosed(false);
    KLocalizedString::setApplicationDomain("sparky-pjeoffice");
    Tray tray;
    tray.startSignerOnce();
    return app.exec();
}

#include "tray.moc"
