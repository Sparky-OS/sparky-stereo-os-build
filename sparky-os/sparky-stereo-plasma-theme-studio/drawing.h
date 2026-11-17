// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QCoreApplication>
#include <QDomDocument>
#include <QImage>
#include <QMap>
#include <QStringList>

class Drawing
{
    Q_DECLARE_TR_FUNCTIONS(Drawing)
public:
    void open(const QString &path, bool square = true);
    int height(int width) const;
    QStringList groups() const;
    QStringList hitGroups(const QPoint &pixel, int width) const;
    void setPlace(const QString &id, qreal place);
    int disparity(const QString &id, int size) const;
    QString groupLabel(const QString &id) const;
    void readLimits(int outputWidth = 0, int displayedWidth = 0);
    void useDefaults();
    Drawing forExport() const;
    QRect partBounds(const QString &id, int size) const;
    int drawingCapacity(const QString &id, int size, bool popped) const;
    int desktopCapacity(const QString &id) const;
    QString depthNotice(const QString &id, int size) const;
    QStringList collapsedWith(const QString &id, int size) const;
    void checkOrder(int size) const;
    qreal sunk() const { return sunkLimit; }
    qreal popped() const { return poppedLimit; }
    QImage eye(int size, bool right, QString only = {}) const;
    QByteArray viewSvg(int size, bool right, QString only = {}) const;
    QByteArray pairSvg(int size) const;
    QMap<QString, qreal> places;
    QByteArray original;
    QString source;
private:
    QDomDocument document;
    qreal sunkLimit = 0;
    qreal poppedLimit = 0;
    int outputPixels = 0;
    int displayedPixels = 0; // zero: the exported canvas is shown at its native pixel size.
    mutable QMap<int, QMap<QString, QRect>> boundsCache;
};

void saveBytes(const QString &path, const QByteArray &bytes);
void savePns(const QString &path, const QImage &left, const QImage &right);
