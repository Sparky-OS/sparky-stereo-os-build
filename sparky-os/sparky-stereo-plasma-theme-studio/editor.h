// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "drawing.h"
#include "preview.h"
#include <QJsonObject>
#include <QLabel>
#include <QTreeWidget>
#include <QSpinBox>
#include <QCheckBox>
#include <QTableWidget>
#include <QUndoStack>
#include <functional>
#include <QTabWidget>
#include <QVBoxLayout>
#include <QTemporaryDir>
#include <QProcess>
#include <memory>

class Editor : public QWidget
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sparky.ThemeEditor1")
public:
    Drawing drawing;
    QString themeRoot;
    QString iconPath;
    QLabel *location;
    QLabel *selection;
    QTreeWidget *groups;
    Preview *preview;
    QSpinBox *size;
    QCheckBox *stereo;
    QTableWidget *disparities;
    QUndoStack *history;
    explicit Editor(bool part = false);
    bool partMode;
    Editor *plasmaEditor = nullptr;
    QTabWidget *pages = nullptr;
    QString plasmaRoot, plasmaPath, colourName;
    QByteArray colourBytes;
    bool membersDirty = false;
    QLabel *colourLabel = nullptr;
    QLabel *projectLocation = nullptr;
    std::unique_ptr<QTemporaryDir> peerWork, plasmaWork;
    QProcess *peer = nullptr;
    void populateGroups();
    void addPlasma(const QString &root, const QString &path);
    void addColour(const QString &path);
    void editColour();
    void explorePlasma();
    void saveParts(const QString &stage, QJsonObject &project);
    void loadParts(const QString &path, const QJsonObject &project);
    void setupParts(QVBoxLayout *layout);
    void startPeer(const QString &program, const QStringList &arguments, bool colour, const QString &workingTheme = {});
    QString makePeerWork();
    bool allClean() const;
    void ensurePeerClosed() const;
    QString importColour(const QByteArray &bytes);
    void guarded(const std::function<void()> &f);
    void load(QString root, QString icon);
    void refresh();
    void applyPlaces(const QJsonObject &object);
    void loadProject(const QString &path);
    void saveProject(const QString &destination);
    void changeDepth(const QString &id, qreal value);
    void restorePlaces(const QMap<QString, qreal> &places);
    QList<int> themeSizes() const;
    QString selectedGroup() const;
    QPoint lastPick{-1000, -1000};
    QStringList pickStack;
    int pickIndex = 0;
    void pickAt(QPointF point);
    bool mayDiscard();
public slots:
    bool selectPart(const QString &id);
    QString addColourFile(const QString &path);
    QString addPlasmaFile(const QString &path);
    QString peerState() const;
    QString setPlasmaDepth(const QString &id, double value);
    QString launchColourEditor();
    QString launchThemeExplorer();
    QString setGroupDepth(const QString &id, double value);
    QString sessionState() const;
    bool setRenderWidth(int width);
    void undoDepth() { history->undo(); }
    void redoDepth() { history->redo(); }
protected:
    void closeEvent(QCloseEvent *event) override;
};
