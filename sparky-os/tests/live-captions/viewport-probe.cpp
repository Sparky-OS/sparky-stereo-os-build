// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
// Test-only observer of the actual installed KCM, loaded into that process only.
#include <QGuiApplication>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include <QFontMetricsF>
#include <QFont>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <algorithm>
static void inspect(QQuickItem *item, QJsonArray &rows, int depth=0) {
    if (depth>80 || !item->isVisible()) return;
    const auto text=item->property("text").toString();
    if (!text.isEmpty() && item->property("contentWidth").isValid()) {
        const auto pos=item->mapToScene(QPointF());
        double left=0,right=item->window()->width();
        QJsonArray ancestors;
        for (auto *parent=item->parentItem();parent;parent=parent->parentItem()) {
            const auto p=parent->mapToScene(QPointF());
            ancestors.append(QJsonObject{{"class",parent->metaObject()->className()},{"width",parent->width()},{"x",p.x()},{"clip",parent->clip()}});
            if (parent->clip()) {left=std::max(left,p.x());right=std::min(right,p.x()+parent->width());}
        }
        // QQuickStyleItem contentWidth is a style size hint, including the widest
        // combo-box menu entry. It is not the glyph width of the current text.
        const bool native=QString(item->metaObject()->className())=="KQuickStyleItem";
        auto *control=item->parentItem();
        const QFont font=qvariant_cast<QFont>(control->property("font"));
        QString display=text;display.remove('&');
        const double content=native ? QFontMetricsF(font).horizontalAdvance(display) : item->property("contentWidth").toDouble();
        const double contentHeight=native ? QFontMetricsF(font).height() : item->property("contentHeight").toDouble();
        const double available=native && control->property("availableWidth").isValid() ? control->property("availableWidth").toDouble() : item->width();
        // Item and rendered text must both fit; scrollable vertical content is allowed.
        bool ok=pos.x()>=left-1 && pos.x()+item->width()<=right+1 && content<=available+1 && contentHeight<=item->height()+1 && !item->property("truncated").toBool();
        rows.append(QJsonObject{{"text",text},{"class",item->metaObject()->className()},{"x",pos.x()},{"y",pos.y()},{"width",item->width()},{"height",item->height()},{"contentWidth",content},{"availableWidth",available},{"nativeStyle",native},{"contentHeight",contentHeight},{"left",left},{"right",right},{"truncated",item->property("truncated").toBool()},{"passed",ok},{"ancestors",ancestors}});
    }
    for(auto *child:item->childItems())inspect(child,rows,depth+1);
}
static void startProbe() {
    auto *timer=new QTimer(qApp);
    QObject::connect(timer,&QTimer::timeout,[](){
        QJsonArray rows;
        for(auto *window:QGuiApplication::allWindows())
            if(auto *quick=qobject_cast<QQuickWindow*>(window);quick)inspect(quick->contentItem(),rows);
        QFile file(qEnvironmentVariable("LC73_VIEWPORT_OUT")+".new");
        if(file.open(QIODevice::WriteOnly)){file.write(QJsonDocument(rows).toJson());file.close();QFile::remove(qEnvironmentVariable("LC73_VIEWPORT_OUT"));file.rename(qEnvironmentVariable("LC73_VIEWPORT_OUT"));}
    });
    timer->start(250);
}
Q_COREAPP_STARTUP_FUNCTION(startProbe)
