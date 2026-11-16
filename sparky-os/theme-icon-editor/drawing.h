// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QDomDocument>
#include <QImage>
#include <QMap>
#include <QStringList>

class Drawing
{
public:
    void open(const QString &path);
    QStringList groups() const;
    void setPlace(const QString &id, int place);
    QImage eye(int size, bool right, QString only = {}) const;
    QByteArray viewSvg(int size, bool right, QString only = {}) const;
    QByteArray pairSvg(int size) const;
    QMap<QString, int> places;
    QByteArray original;
    QString source;
private:
    QDomDocument document;
};

void saveBytes(const QString &path, const QByteArray &bytes);
void savePns(const QString &path, const QImage &left, const QImage &right);
