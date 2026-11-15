// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// One V4L2 capture device, asked through the kernel's own ioctls (linux/videodev2.h; the V4L2 API specification,
// "Querying Capabilities", "Image Format Enumeration", "Extended Controls"). Controls are set on the device, so every
// program that opens it sees them.
namespace Sparky::Camera
{
struct Result {
    bool ok = true;
    int error = 0; // errno of the ioctl that failed
    QString what; // the ioctl or step, for a log: never shown as the whole message
};

struct Size {
    int width = 0;
    int height = 0;
    bool operator==(const Size &o) const { return width == o.width && height == o.height; }
};

// A frame size the driver lists: one discrete size, or a stepwise range the page offers as it is
struct SizeEntry {
    bool stepwise = false;
    Size size; // discrete size, or the range's minimum
    Size max;
    Size step;
};

struct Format {
    QString fourcc; // "YUYV", "MJPG"
    QString description;
    bool compressed = false;
    QList<SizeEntry> sizes;
};

struct Mode {
    QString fourcc;
    Size size;
    double fps = 0;
};

struct Control {
    enum Kind { Integer, Boolean, Menu, IntegerMenu, Button, Other };
    quint32 id = 0;
    QString name;
    Kind kind = Other;
    qint64 minimum = 0;
    qint64 maximum = 0;
    qint64 step = 1;
    qint64 defaultValue = 0;
    qint64 value = 0;
    bool inactive = false; // the driver says the control has no effect now (V4L2_CTRL_FLAG_INACTIVE)
    bool readOnly = false;
    bool grabbed = false; // another program holds it
    struct MenuItem {
        qint64 index;
        QString text;
    };
    QList<MenuItem> menu;
    QString otherKind; // the kernel's type name for a kind the page cannot edit
};

class V4l2Camera
{
public:
    explicit V4l2Camera(const QString &path);
    ~V4l2Camera();
    V4l2Camera(const V4l2Camera &) = delete;
    V4l2Camera &operator=(const V4l2Camera &) = delete;

    bool isOpen() const { return m_fd >= 0; }
    int openError() const { return m_openError; }
    QString path() const { return m_path; }
    QString card() const { return m_card; }
    QString driver() const { return m_driver; }
    QString busInfo() const { return m_bus; }
    bool canCapture() const { return m_capture; }

    QList<Format> formats();
    // The frame rates for one size, as numbers of frames a second; a stepwise range is listed by its limits
    QList<double> frameRates(const QString &fourcc, Size size);
    Mode currentMode();
    Result setMode(const Mode &mode);

    QList<Control> controls();
    Result setControl(quint32 id, qint64 value);
    // Every control that is not read-only, inactive or a button, back to the driver's default
    Result resetControls(QStringList *failed = nullptr);

    static QString fourccText(quint32 code);
    static quint32 fourccCode(const QString &text);
    // The sentence the page shows for a failed ioctl: what happened and what to do (translated)
    static QString explain(const Result &result, const QString &subject);

private:
    int m_fd = -1;
    int m_openError = 0;
    QString m_path;
    QString m_card;
    QString m_driver;
    QString m_bus;
    bool m_capture = false;
};
}
