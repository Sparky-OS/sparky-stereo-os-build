// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "backend.h"
#include <QWidget>
#include <functional>
#include <QComboBox>
#include <QLabel>
#include <QPushButton>
#include <QSlider>

class Window : public QWidget
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sparky.UMS.Controller")
public:
    explicit Window(const QUrl &server);
    QString execute(std::function<void()> action);
public Q_SLOTS:
    void Open(const QString &target, const QString &url);
private:
    void refresh();
    void selected();
    Backend backend;
    QComboBox *devices;
    QLabel *status;
    QLabel *error;
    QLabel *file;
    QPushButton *send;
    QPushButton *play;
    QPushButton *pause;
    QPushButton *stop;
    QPushButton *back;
    QPushButton *forward;
    QSlider *volume;
    QSlider *brightness;
    QWidget *brightnessRow;
    QUrl source;
    QString kind;
    QString mprisName;
    bool busy = false;
    QObject *mprisObject;
};
