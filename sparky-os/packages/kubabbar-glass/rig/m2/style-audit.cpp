// SPDX-License-Identifier: GPL-3.0-only
#include <QApplication>
#include <QFont>
#include <QPalette>
#include <QStyle>
#include <QTimer>
#include <QDebug>
#include <dlfcn.h>

int QCoreApplication::exec()
{
    QTimer::singleShot(4000, [] {
        if (!qobject_cast<QApplication *>(QCoreApplication::instance())) return;
        const auto palette = QApplication::palette();
        qInfo().noquote() << "STYLE_AUDIT" << QCoreApplication::applicationName()
                         << "style=" << QApplication::style()->metaObject()->className()
                         << "name=" << QApplication::style()->objectName()
                         << "font=" << QApplication::font().toString();
        for (auto group : {QPalette::Active, QPalette::Inactive}) {
            qInfo().noquote() << "PALETTE_AUDIT" << group
                << "window=" << palette.color(group, QPalette::Window).name()
                << "base=" << palette.color(group, QPalette::Base).name()
                << "button=" << palette.color(group, QPalette::Button).name()
                << "highlight=" << palette.color(group, QPalette::Highlight).name()
                << "text=" << palette.color(group, QPalette::Text).name();
        }
    });
    auto original = reinterpret_cast<int (*)()>(dlsym(RTLD_NEXT, "_ZN16QCoreApplication4execEv"));
    return original();
}
