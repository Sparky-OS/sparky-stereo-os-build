// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include <stereo-layer/widgetlayer.h>
#include <stereo-layer/picture.h>
#include <KConfig>
#include <KConfigGroup>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCommandLineParser>
#include <QCryptographicHash>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QMessageBox>
#include <QPainter>
#include <QProcess>
#include <QPushButton>
#include <QSettings>
#include <QSet>
#include <QSignalBlocker>
#include <QSpinBox>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimer>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <filesystem>
#include <functional>
#include <iostream>

class Preview : public QWidget
{
public:
    Stereo::WidgetLayer *layer;
    QImage left;
    Preview() { setFixedSize(256, 256); layer = new Stereo::WidgetLayer(this); layer->setPaintArea(false); }
    void setViews(const QImage &a, const QImage &b, bool stereo)
    {
#ifdef PREVIEW_REFERENCE
        stereo = false;
#endif
        left = a;
        if (stereo) {
            QImage pair(a.width() * 2, a.height(), a.format());
            pair.fill(Qt::transparent);
            { QPainter p(&pair); p.setCompositionMode(QPainter::CompositionMode_Source); p.drawImage(0, 0, a); p.drawImage(a.width(), 0, b); }
            layer->setPicture(Stereo::Picture::fromPackedImage(pair, Stereo::Picture::Layout::SideBySide, Stereo::Picture::EyeOrder::LeftFirst));
        } else { Stereo::Picture flat; flat.original = a; layer->setPicture(flat); }
        update();
    }
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(rect(), Qt::black);
        layer->paint(&p);
    }
};

class Editor : public QWidget
{
public:
    Drawing drawing;
    QString themeRoot;
    QString iconPath;
    QLabel *location;
    QTreeWidget *groups;
    Preview *preview;
    QSpinBox *size;
    QCheckBox *stereo;
    Editor()
    {
        Stereo::WidgetLayer::prepareWindow(this);
        setWindowTitle(tr("Icon theme"));
        resize(820, 520);
        auto *layout = new QVBoxLayout(this);
        auto *actions = new QHBoxLayout;
        auto *open = new QPushButton(tr("Open icon theme…"));
        auto *save = new QPushButton(tr("Save a project copy…"));
        stereo = new QCheckBox(tr("Enable 3D"));
        stereo->setChecked(true);
        size = new QSpinBox;
        size->setRange(8, 2048);
        size->setValue(256);
        size->setPrefix(tr("Pixels per view: "));
        auto *settings = new QPushButton(tr("Display Settings…"));
        for (auto *w : QList<QWidget *>{open, save, stereo, size, settings}) actions->addWidget(w);
        layout->addLayout(actions);
        location = new QLabel(tr("Open a theme; the source stays read only until you save a project copy."));
        location->setWordWrap(true);
        layout->addWidget(location);
        auto *body = new QHBoxLayout;
        groups = new QTreeWidget;
        groups->setHeaderLabels({tr("SVG group"), tr("Place")});
        preview = new Preview;
        body->addWidget(groups, 1);
        body->addWidget(preview, 0, Qt::AlignCenter);
        layout->addLayout(body);
        connect(open, &QPushButton::clicked, this, [this] { guarded([&] {
            auto root = QFileDialog::getExistingDirectory(this, tr("Icon theme folder"));
            if (root.isEmpty()) return;
            if (QFile::exists(root + "/project.json")) { loadProject(root); return; }
            auto icon = QFileDialog::getOpenFileName(this, tr("SVG source"), root, "SVG (*.svg *.svgz)");
            if (!icon.isEmpty()) load(root, icon);
        }); });
        connect(save, &QPushButton::clicked, this, [this] { guarded([&] {
            auto destination = QFileDialog::getSaveFileName(this, tr("New project folder"), QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/theme-project");
            if (!destination.isEmpty()) saveProject(destination);
        }); });
        connect(stereo, &QCheckBox::toggled, this, [this] { refresh(); });
        connect(size, &QSpinBox::valueChanged, this, [this] { guarded([&] { refresh(); }); });
        connect(settings, &QPushButton::clicked, this, [this] {
            if (!QProcess::startDetached("kcmshell6", {"kcm_kscreen"})) QMessageBox::critical(this, tr("Display Settings"), tr("Cannot start Display Settings (kcmshell6)."));
        });
        connect(preview->layer, &Stereo::WidgetLayer::failureChanged, this, [this] {
            if (!preview->layer->failure().isEmpty()) location->setText(preview->layer->failure());
        });
    }
    void guarded(const std::function<void()> &f)
    {
        try { f(); } catch (const std::exception &e) { QMessageBox::critical(this, tr("Cannot complete the operation"), QString::fromUtf8(e.what())); }
    }
    void load(QString root, QString icon)
    {
        root = QFileInfo(root).canonicalFilePath();
        icon = QFileInfo(icon).canonicalFilePath();
        if (root.isEmpty() || !QFile::exists(root + "/index.theme") || !icon.startsWith(root + "/"))
            throw std::runtime_error("Choose an icon inside a readable theme with index.theme");
        Drawing next;
        next.open(icon);
        drawing = next;
        themeRoot = root;
        iconPath = QDir(root).relativeFilePath(icon);
        groups->clear();
        for (const QString &id : drawing.groups()) {
            auto *item = new QTreeWidgetItem(groups, {id});
            auto *place = new QComboBox;
            place->addItems({tr("Sunk"), tr("Screen"), tr("Popped")});
            place->setCurrentIndex(1);
            groups->setItemWidget(item, 1, place);
            connect(place, &QComboBox::currentIndexChanged, this, [this, id, place](int index) {
                const int old = drawing.places.value(id);
                try { drawing.setPlace(id, index - 1); refresh(); }
                catch (const std::exception &e) {
                    QSignalBlocker block(place); place->setCurrentIndex(old + 1);
                    QMessageBox::critical(this, tr("Cannot set this place"), QString::fromUtf8(e.what()));
                }
            });
        }
        location->setText(tr("Read only source: %1. Save creates a separate project copy.").arg(root));
        refresh();
    }
    void refresh()
    {
        if (drawing.source.isEmpty()) return;
        drawing.readLimits();
        preview->setViews(drawing.eye(size->value(), false), drawing.eye(size->value(), true), stereo->isChecked());
    }
    void applyPlaces(const QJsonObject &object)
    {
        Drawing candidate = drawing;
        for (auto i = candidate.places.begin(); i != candidate.places.end(); ++i) i.value() = 0;
        for (auto i = object.begin(); i != object.end(); ++i) {
            if (!i.value().isDouble() || i.value().toDouble() != i.value().toInt())
                throw std::runtime_error("A group place must be an integer");
            candidate.setPlace(i.key(), i.value().toInt());
        }
        drawing.places = candidate.places;
        for (int i = 0; i < groups->topLevelItemCount(); ++i) {
            auto *item = groups->topLevelItem(i);
            auto *combo = static_cast<QComboBox *>(groups->itemWidget(item, 1));
            QSignalBlocker block(combo);
            combo->setCurrentIndex(drawing.places.value(item->text(0)) + 1);
        }
        refresh();
    }
    void loadProject(const QString &path)
    {
        QFile file(path + "/project.json");
        if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error("Cannot read the project");
        QJsonParseError error;
        auto data = QJsonDocument::fromJson(file.readAll(), &error);
        auto project = data.object();
        if (error.error != QJsonParseError::NoError || project.value("version").toInt() != 1
            || !project.value("icon").isString() || !project.value("groups").isObject())
            throw std::runtime_error("Invalid or unsupported theme project");
        load(path + "/icons", path + "/icons/" + project.value("icon").toString());
        applyPlaces(project.value("groups").toObject());
        location->setText(tr("Project copy: %1").arg(path));
    }
    void saveProject(const QString &destination)
    {
        if (drawing.source.isEmpty()) throw std::runtime_error("Open a source first");
        drawing.readLimits();
        if (QFileInfo::exists(destination)) throw std::runtime_error("The project destination already exists; choose a new folder");
        const auto parent = QFileInfo(destination).absolutePath();
        const QString canonicalParent = QFileInfo(parent).canonicalFilePath();
        if (canonicalParent == themeRoot || canonicalParent.startsWith(themeRoot + "/"))
            throw std::runtime_error("Save the copy outside its source theme");
        QTemporaryDir stage(parent + "/.theme-editor-XXXXXX");
        if (!stage.isValid()) throw std::runtime_error("Cannot create the project beside its destination");
        namespace fs = std::filesystem;
        fs::copy(themeRoot.toStdString(), (stage.path() + "/icons").toStdString(), fs::copy_options::recursive | fs::copy_options::copy_symlinks);
        if (QFileInfo(stage.path() + "/icons/index.theme").isSymLink())
            throw std::runtime_error("A project index must be a regular file");
        const QString copiedIndex = stage.path() + "/icons/index.theme";
        if (!QFile::setPermissions(copiedIndex, QFile::permissions(copiedIndex) | QFileDevice::WriteOwner))
            throw std::runtime_error("Cannot make the copied index writable");
        fs::permissions((stage.path() + "/icons").toStdString(), fs::perms::owner_write | fs::perms::owner_exec, fs::perm_options::add);
        QString outputRoot = "stereo-authored";
        for (int generation = 2; QFileInfo::exists(stage.path() + "/icons/" + outputRoot); ++generation)
            outputRoot = QString("stereo-authored-%1").arg(generation);
        KConfig sourceIndex(themeRoot + "/index.theme", KConfig::SimpleConfig);
        QSet<int> sizes;
        QMap<QString, QString> contexts;
        for (const QString &section : sourceIndex.groupList()) {
            KConfigGroup group(&sourceIndex, section);
            const int n = group.readEntry("Size", 0);
            if (n > 2048) throw std::runtime_error("A declared size exceeds this slice's 2048 pixel render limit");
            if (n > 0) sizes.insert(n);
            const auto context = group.readEntry("Context", QString());
            if (!context.isEmpty()) contexts[section.section('/', -1)] = context;
        }
        if (sizes.isEmpty()) throw std::runtime_error("The theme declares no usable sizes");
        QString contextDirectory;
        const auto parts = iconPath.split('/');
        for (int i = parts.size() - 2; i >= 0; --i)
            if (contexts.contains(parts[i])) { contextDirectory = parts[i]; break; }
        if (contextDirectory.isEmpty()) throw std::runtime_error("This slice needs an SVG source under a context declared in index.theme");
        QJsonObject levels;
        for (auto i = drawing.places.cbegin(); i != drawing.places.cend(); ++i) levels[i.key()] = i.value();
        QJsonObject project{{"version", 1}, {"icon", iconPath}, {"groups", levels},
            {"export-limits", QJsonObject{{"sunk", drawing.sunk()}, {"popped", drawing.popped()}}},
            {"source-sha256", QString::fromLatin1(QCryptographicHash::hash(drawing.original, QCryptographicHash::Sha256).toHex())}};
        QStringList stereoDirectories;
        for (int n : sizes) {
            const QString directory = QString("%1/%2x%2/%3").arg(outputRoot).arg(n).arg(contextDirectory);
            stereoDirectories << directory;
            QDir().mkpath(stage.path() + "/icons/" + directory);
            QDir().mkpath(stage.path() + "/pairs");
            saveBytes(stage.path() + "/icons/" + directory + "/" + QFileInfo(iconPath).completeBaseName() + ".svg", drawing.pairSvg(n));
            savePns(stage.path() + QString("/pairs/%1.pns").arg(n), drawing.eye(n, false), drawing.eye(n, true));
        }
        {
            KConfig index(stage.path() + "/icons/index.theme", KConfig::SimpleConfig);
            KConfigGroup theme(&index, "Icon Theme");
            const auto oldDirectories = theme.readEntry("X-StereoDirectories", QStringList());
            theme.writeEntry("X-StereoDirectories", stereoDirectories + oldDirectories);
            for (int n : sizes) {
                KConfigGroup group(&index, QString("%1/%2x%2/%3").arg(outputRoot).arg(n).arg(contextDirectory));
                group.writeEntry("X-StereoSize", n);
                group.writeEntry("X-StereoLayout", "sbs-left-first");
                group.writeEntry("Type", "Fixed");
                group.writeEntry("Context", contexts.value(contextDirectory));
            }
            if (!index.sync()) throw std::runtime_error("Cannot save the copied theme index");
        }
        saveBytes(stage.path() + "/project.json", QJsonDocument(project).toJson());
        if (!QDir().rename(stage.path(), destination)) throw std::runtime_error("Cannot commit the project folder");
        stage.setAutoRemove(false);
        location->setText(tr("Saved project copy: %1").arg(destination));
    }
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QCommandLineParser parser;
    parser.addHelpOption();
    for (const QString name : {"theme", "icon", "project", "places", "save"}) parser.addOption({name, name, "path"});
    parser.addOption({"flat", "Disable the stereo preview"});
    parser.addOption({"exit-after-save", "Return after the requested save"});
    parser.process(app);
    try {
        Editor editor;
        if (parser.isSet("project")) editor.loadProject(parser.value("project"));
        else if (parser.isSet("theme")) editor.load(parser.value("theme"), parser.value("icon"));
        if (parser.isSet("places")) {
            QFile file(parser.value("places"));
            if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error("Cannot open the group choices");
            QJsonParseError error;
            const auto data = QJsonDocument::fromJson(file.readAll(), &error);
            if (error.error != QJsonParseError::NoError || !data.isObject()) throw std::runtime_error("Invalid group choices");
            editor.applyPlaces(data.object());
        }
        if (parser.isSet("flat")) editor.stereo->setChecked(false);
        if (parser.isSet("save")) editor.saveProject(parser.value("save"));
        if (parser.isSet("exit-after-save")) return 0;
        editor.show();
        return app.exec();
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
