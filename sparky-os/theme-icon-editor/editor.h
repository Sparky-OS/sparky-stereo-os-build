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
    Editor();
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
    bool mayDiscard();
public slots:
    bool selectPart(const QString &id);
    QString setGroupDepth(const QString &id, double value);
    QString sessionState() const;
    void undoDepth() { history->undo(); }
    void redoDepth() { history->redo(); }
protected:
    void closeEvent(QCloseEvent *event) override;
};
