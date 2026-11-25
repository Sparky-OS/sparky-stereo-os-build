// SPDX-License-Identifier: GPL-3.0-or-later
#include <KLocalizedString>
#include <KPluginFactory>
#include <KPropertiesDialog>
#include <KPropertiesDialogPlugin>
#include <QDir>
#include <QLabel>
#include <QProcess>
#include <QPushButton>
#include <QStorageInfo>
#include <QVBoxLayout>

using namespace Qt::StringLiterals;

class DriveProperties : public KPropertiesDialogPlugin
{
    Q_OBJECT
public:
    explicit DriveProperties(QObject *parent, const KPluginMetaData &)
        : KPropertiesDialogPlugin(parent)
    {
        if (properties->items().count() != 1 || !properties->url().isLocalFile()) return;
        const auto path = QDir::cleanPath(properties->url().toLocalFile());
        const QStorageInfo volume(path);
        if (!volume.isValid() || !volume.isReady() || volume.rootPath() != path) return;
        auto page = new QWidget(properties);
        auto layout = new QVBoxLayout(page);
        auto label = new QLabel(i18n("Review what you can remove"), page);
        auto button = new QPushButton(i18n("Clean up…"), page);
        layout->addWidget(label);
        layout->addWidget(button, 0, Qt::AlignLeft);
        layout->addStretch();
        connect(button, &QPushButton::clicked, page, [label, path] {
            if (!QProcess::startDetached(u"/usr/bin/sparky-open-storage-cleanup"_s, {path}))
                label->setText(i18n("Storage Cleanup could not be opened."));
        });
        properties->addPage(page, i18n("Storage Cleanup"));
    }
};

K_PLUGIN_CLASS_WITH_JSON(DriveProperties, "driveproperties.json")
#include "driveproperties.moc"
