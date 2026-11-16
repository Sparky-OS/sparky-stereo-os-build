// SPDX-License-Identifier: GPL-2.0-or-later
#include "editor.h"
#include <QApplication>
#include <QCryptographicHash>
#include <QDirIterator>
#include <QJsonDocument>
#include <QPainter>
#include <QSvgRenderer>
#include <QTemporaryDir>
#include <iostream>
#include <filesystem>

static void require(bool value, const char *message)
{
    if (!value) throw std::runtime_error(message);
}
static QByteArray bytes(const QString &path)
{
    QFile f(path); require(f.open(QIODevice::ReadOnly), "Cannot read test input"); return f.readAll();
}
static int difference(const QImage &a, const QImage &b)
{
    require(a.size() == b.size(), "Image sizes differ");
    int maximum = 0;
    for (int y = 0; y < a.height(); ++y)
        for (int x = 0; x < a.width(); ++x) {
            const QRgb p = a.pixel(x, y), q = b.pixel(x, y);
            for (int shift : {0, 8, 16, 24}) maximum = qMax(maximum, qAbs(int((p >> shift) & 255) - int((q >> shift) & 255)));
        }
    return maximum;
}
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc != 2) return 2;
    try {
        const QString fixtures = QString::fromLocal8Bit(argv[1]);
        const QString path = fixtures + "/plasma/widgets/panel-background.svg";
        const auto original = bytes(path), colour = bytes(fixtures + "/Project.colors");
        Editor editor;
        editor.loadProject(fixtures + "/project");
        editor.stereo->setChecked(false);
        const auto iconPlaces = editor.drawing.places;
        editor.addPlasma(fixtures + "/plasma", path);
        editor.addColour(fixtures + "/Project.colors");
        require(!editor.plasmaEditor->stereo->isChecked(), "Flat mode did not reach the Plasma preview");
        editor.plasmaEditor->stereo->setChecked(true);
        require(editor.stereo->isChecked(), "Enable 3D differs between document tabs");
        auto &part = editor.plasmaEditor->drawing;
        const auto zero = part.eye(256, false);
        require(zero.size() == QSize(256, 163), "Plasma canvas aspect ratio lost");
        QImage reference(zero.size(), zero.format()); reference.fill(Qt::transparent);
        { QPainter painter(&reference); QSvgRenderer renderer(original); renderer.render(&painter); }
        require(difference(zero, reference) <= 1, "Plasma zero-depth differs from original KDE artwork");
        require(editor.setPlasmaDepth("south-center", -1).isEmpty(), "Cannot edit real Plasma group");
        const auto a = part.eye(256, false), b = part.eye(256, true);
        require(a != b, "Plasma group has no measured disparity");
        const auto isolatedA = part.eye(256, false, "south-center"), isolatedB = part.eye(256, true, "south-center");
        int minA = 256, minB = 256;
        for (int y = 0; y < a.height(); ++y)
            for (int x = 0; x < a.width(); ++x) {
                if (qAlpha(isolatedA.pixel(x, y)) > 128) minA = qMin(minA, x);
                if (qAlpha(isolatedB.pixel(x, y)) > 128) minB = qMin(minB, x);
            }
        require(minA - minB == part.disparity("south-center", 256), "Plasma disparity does not match KWin operation");
        QImage pair(512, 163, a.format()); pair.fill(Qt::transparent);
        { QPainter painter(&pair); QSvgRenderer renderer(part.pairSvg(256)); renderer.render(&painter); }
        require(difference(pair.copy(0, 0, 256, 163), a) <= 1 && difference(pair.copy(256, 0, 256, 163), b) <= 1, "Plasma SVG pair does not reproduce both views");
        editor.plasmaEditor->history->undo(); require(part.eye(256, false) == zero, "Plasma undo lost artwork");
        editor.plasmaEditor->history->redo(); require(part.eye(256, false) == a, "Plasma redo lost depth");
        require(editor.drawing.places == iconPlaces, "Plasma editing changed icon depths");
        const auto working = editor.makePeerWork() + "/data/plasma/desktoptheme/test";
        QDir().mkpath(QFileInfo(working).absolutePath());
        std::filesystem::copy((fixtures + "/plasma").toStdString(), working.toStdString(), std::filesystem::copy_options::recursive);
        editor.startPeer("/bin/sh", {"-c", "printf '[General]\\nName=RoundTrip\\n' > \"$XDG_DATA_HOME/plasma/desktoptheme/test/colors\""}, false, working);
        require(editor.peer->waitForFinished(5000), "External editor did not finish");
        require(editor.plasmaRoot == working && bytes(editor.plasmaRoot + "/colors").contains("RoundTrip"), "External Plasma edits were discarded");
        require(part.places.value("south-center") == -1, "External round trip lost authored depth");
        require(!QFile::exists(fixtures + "/plasma/colors"), "External editor wrote to the original theme");
        QTemporaryDir output;
        editor.saveProject(output.path() + "/shared");
        require(!editor.isWindowModified(), "Saved project still displays unsaved changes");
        require(bytes(output.path() + "/shared/plasma/widgets/panel-background.svg") == original, "Saved ordinary Plasma source changed");
        require(bytes(output.path() + "/shared/color-schemes/Project.colors") == colour, "Saved colour scheme changed");
        Editor reopened; reopened.loadProject(output.path() + "/shared");
        require(reopened.plasmaEditor && reopened.plasmaEditor->drawing.places == part.places, "Plasma depths did not round trip");
        require(reopened.colourBytes == colour && reopened.drawing.places == iconPlaces && reopened.allClean(), "Shared project did not round trip cleanly");
        require(bytes(path) == original && bytes(fixtures + "/Project.colors") == colour, "Input was modified");
        require(!reopened.addPlasmaFile(fixtures + "/Project.colors").isEmpty(), "Invalid Plasma input accepted");
        QTemporaryDir linked;
        const auto linkedRoot = linked.path() + "/source";
        std::filesystem::copy((fixtures + "/plasma").toStdString(), linkedRoot.toStdString(), std::filesystem::copy_options::recursive);
        saveBytes(linkedRoot + "/palette", "original");
        std::filesystem::create_symlink("palette", (linkedRoot + "/colors").toStdString());
        const auto tools = linked.path() + "/tools"; QDir().mkpath(tools);
        saveBytes(tools + "/plasmathemeexplorer", "#!/bin/sh\nsleep 1\n");
        QFile::setPermissions(tools + "/plasmathemeexplorer", QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        const auto savedPath = qgetenv("PATH"); qputenv("PATH", tools.toUtf8() + ":" + savedPath);
        Editor safe;
        safe.loadProject(fixtures + "/project"); safe.addPlasma(linkedRoot, linkedRoot + "/widgets/panel-background.svg");
        safe.explorePlasma();
        const auto copy = safe.peerWork->path() + "/data/plasma/desktoptheme/sparky-stereo-oxygen";
        require(!QFileInfo(copy + "/colors").isSymLink(), "Native tool receives a source symlink");
        saveBytes(copy + "/colors", "changed");
        require(safe.peer->waitForFinished(5000), "Native-tool bridge did not finish");
        require(bytes(linkedRoot + "/palette") == "original" && bytes(safe.plasmaRoot + "/colors") == "changed", "Native tool changed the original alias target");
        saveBytes(linked.path() + "/outside", "private");
        std::filesystem::create_symlink((linked.path() + "/outside").toStdString(), (linkedRoot + "/outside-link").toStdString());
        Editor refused; refused.loadProject(fixtures + "/project"); refused.addPlasma(linkedRoot, linkedRoot + "/widgets/panel-background.svg");
        bool rejected = false;
        try { refused.explorePlasma(); } catch (const std::exception &e) { rejected = QString::fromUtf8(e.what()).contains("outside or cyclic link"); }
        require(rejected && bytes(linked.path() + "/outside") == "private", "Outside theme link was followed");
        QFile::remove(linkedRoot + "/outside-link");
        std::filesystem::create_directory_symlink(linkedRoot.toStdString(), (linkedRoot + "/cycle").toStdString());
        rejected = false;
        try { refused.explorePlasma(); } catch (const std::exception &e) { rejected = QString::fromUtf8(e.what()).contains("outside or cyclic link"); }
        require(rejected, "Cyclic theme link was followed");
        qputenv("PATH", savedPath);
        std::cout << "PASS: shared icon/colour/Plasma project; original aspect and pixels; measured disparity=" << minA-minB << "; undo/redo; paired SVG; save/reopen; sources unchanged\n";
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
