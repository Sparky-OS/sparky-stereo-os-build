// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "preview.h"
#include <QDoubleSpinBox>
#include <QJsonObject>
#include <QLabel>
#include <QMap>
#include <QTemporaryDir>
#include <QWidget>
class Editor;
class ModelPage : public QWidget {
public:
    Editor* editor;
    Preview* preview;
    QLabel *sourceLabel, *summary;
    QDoubleSpinBox* depth;
    QString source;
    QMap<QString, QByteArray> sourceFingerprints;
    double committedDepth = 0;
    void restoreDepth(double value);
    QMap<QString, QJsonObject> metadata;
    QMap<QString, QPair<QImage, QImage>> images;
    ModelPage(Editor* owner);
    QJsonObject render(int n, bool common, bool flat, QImage* left = nullptr, QImage* right = nullptr);
    void open(const QString& path);
    void refresh();
    void exportPairs(const QString& destination);
    void saveProject(const QString& destination);
    void loadProject(const QString& path, const QJsonObject& project);
    QString state() const;
};
