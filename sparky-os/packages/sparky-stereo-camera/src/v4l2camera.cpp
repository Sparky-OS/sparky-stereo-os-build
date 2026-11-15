// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "v4l2camera.h"

#include <KLocalizedString>
#include <QtGlobal>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <unistd.h>

using namespace Sparky::Camera;

namespace
{
// ioctl that retries after a signal, as the V4L2 specification asks
int xioctl(int fd, unsigned long request, void *arg)
{
    int r;
    do {
        r = ::ioctl(fd, request, arg);
    } while (r == -1 && errno == EINTR);
    return r;
}

Control::Kind kindOf(quint32 type)
{
    switch (type) {
    case V4L2_CTRL_TYPE_INTEGER:
        return Control::Integer;
    case V4L2_CTRL_TYPE_BOOLEAN:
        return Control::Boolean;
    case V4L2_CTRL_TYPE_MENU:
        return Control::Menu;
    case V4L2_CTRL_TYPE_INTEGER_MENU:
        return Control::IntegerMenu;
    case V4L2_CTRL_TYPE_BUTTON:
        return Control::Button;
    default:
        return Control::Other;
    }
}

QString otherKindName(quint32 type)
{
    switch (type) {
    case V4L2_CTRL_TYPE_INTEGER64:
        return QStringLiteral("integer64");
    case V4L2_CTRL_TYPE_BITMASK:
        return QStringLiteral("bitmask");
    case V4L2_CTRL_TYPE_STRING:
        return QStringLiteral("string");
    case V4L2_CTRL_TYPE_U8:
    case V4L2_CTRL_TYPE_U16:
    case V4L2_CTRL_TYPE_U32:
        return QStringLiteral("array");
    default:
        return QStringLiteral("type %1").arg(type);
    }
}
}

V4l2Camera::V4l2Camera(const QString &path)
    : m_path(path)
{
    m_fd = ::open(path.toLocal8Bit().constData(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (m_fd < 0) {
        m_openError = errno;
        return;
    }
    v4l2_capability cap;
    std::memset(&cap, 0, sizeof cap);
    if (xioctl(m_fd, VIDIOC_QUERYCAP, &cap) < 0) {
        m_openError = errno;
        ::close(m_fd);
        m_fd = -1;
        return;
    }
    m_card = QString::fromLocal8Bit(reinterpret_cast<const char *>(cap.card));
    m_driver = QString::fromLocal8Bit(reinterpret_cast<const char *>(cap.driver));
    m_bus = QString::fromLocal8Bit(reinterpret_cast<const char *>(cap.bus_info));
    const quint32 caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS) ? cap.device_caps : cap.capabilities;
    m_capture = caps & (V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_VIDEO_CAPTURE_MPLANE);
}

V4l2Camera::~V4l2Camera()
{
    if (m_fd >= 0) {
        ::close(m_fd);
    }
}

QString V4l2Camera::fourccText(quint32 code)
{
    char text[5] = {char(code & 0xff), char((code >> 8) & 0xff), char((code >> 16) & 0xff), char((code >> 24) & 0xff), 0};
    return QString::fromLatin1(text);
}

quint32 V4l2Camera::fourccCode(const QString &text)
{
    const QByteArray b = text.toLatin1().leftJustified(4, ' ');
    return v4l2_fourcc(b[0], b[1], b[2], b[3]);
}

QList<Format> V4l2Camera::formats()
{
    QList<Format> result;
    for (quint32 i = 0;; ++i) {
        v4l2_fmtdesc d;
        std::memset(&d, 0, sizeof d);
        d.index = i;
        d.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (xioctl(m_fd, VIDIOC_ENUM_FMT, &d) < 0) {
            break;
        }
        Format f;
        f.fourcc = fourccText(d.pixelformat);
        f.description = QString::fromLocal8Bit(reinterpret_cast<const char *>(d.description));
        f.compressed = d.flags & V4L2_FMT_FLAG_COMPRESSED;
        for (quint32 s = 0;; ++s) {
            v4l2_frmsizeenum fs;
            std::memset(&fs, 0, sizeof fs);
            fs.index = s;
            fs.pixel_format = d.pixelformat;
            if (xioctl(m_fd, VIDIOC_ENUM_FRAMESIZES, &fs) < 0) {
                break;
            }
            SizeEntry e;
            if (fs.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
                e.size = {int(fs.discrete.width), int(fs.discrete.height)};
            } else {
                e.stepwise = true;
                e.size = {int(fs.stepwise.min_width), int(fs.stepwise.min_height)};
                e.max = {int(fs.stepwise.max_width), int(fs.stepwise.max_height)};
                e.step = {int(fs.stepwise.step_width), int(fs.stepwise.step_height)};
            }
            f.sizes.append(e);
            if (fs.type != V4L2_FRMSIZE_TYPE_DISCRETE) {
                break; // a range comes as one entry
            }
        }
        result.append(f);
    }
    return result;
}

QList<double> V4l2Camera::frameRates(const QString &fourcc, Size size)
{
    QList<double> rates;
    for (quint32 i = 0;; ++i) {
        v4l2_frmivalenum fi;
        std::memset(&fi, 0, sizeof fi);
        fi.index = i;
        fi.pixel_format = fourccCode(fourcc);
        fi.width = size.width;
        fi.height = size.height;
        if (xioctl(m_fd, VIDIOC_ENUM_FRAMEINTERVALS, &fi) < 0) {
            break;
        }
        if (fi.type == V4L2_FRMIVAL_TYPE_DISCRETE) {
            rates.append(double(fi.discrete.denominator) / fi.discrete.numerator);
        } else {
            rates.append(double(fi.stepwise.max.denominator) / fi.stepwise.max.numerator);
            rates.append(double(fi.stepwise.min.denominator) / fi.stepwise.min.numerator);
            break;
        }
    }
    return rates;
}

Mode V4l2Camera::currentMode()
{
    Mode mode;
    v4l2_format f;
    std::memset(&f, 0, sizeof f);
    f.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(m_fd, VIDIOC_G_FMT, &f) == 0) {
        mode.fourcc = fourccText(f.fmt.pix.pixelformat);
        mode.size = {int(f.fmt.pix.width), int(f.fmt.pix.height)};
    }
    v4l2_streamparm p;
    std::memset(&p, 0, sizeof p);
    p.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(m_fd, VIDIOC_G_PARM, &p) == 0 && p.parm.capture.timeperframe.numerator) {
        mode.fps = double(p.parm.capture.timeperframe.denominator) / p.parm.capture.timeperframe.numerator;
    }
    return mode;
}

Result V4l2Camera::setMode(const Mode &mode)
{
    const Mode before = currentMode();
    v4l2_format f;
    std::memset(&f, 0, sizeof f);
    f.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    f.fmt.pix.width = mode.size.width;
    f.fmt.pix.height = mode.size.height;
    f.fmt.pix.pixelformat = fourccCode(mode.fourcc);
    f.fmt.pix.field = V4L2_FIELD_ANY;
    if (xioctl(m_fd, VIDIOC_S_FMT, &f) < 0) {
        return {false, errno, QStringLiteral("VIDIOC_S_FMT")};
    }
    // A driver may adjust the request: say so instead of reporting success for another mode
    if (f.fmt.pix.pixelformat != fourccCode(mode.fourcc) || int(f.fmt.pix.width) != mode.size.width || int(f.fmt.pix.height) != mode.size.height) {
        return {false, ERANGE, QStringLiteral("VIDIOC_S_FMT adjusted the mode")};
    }
    if (mode.fps > 0) {
        v4l2_streamparm p;
        std::memset(&p, 0, sizeof p);
        p.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        p.parm.capture.timeperframe.numerator = 1000;
        p.parm.capture.timeperframe.denominator = quint32(mode.fps * 1000 + 0.5);
        if (xioctl(m_fd, VIDIOC_S_PARM, &p) < 0) {
            const int error = errno;
            // the frame rate was refused after the format was taken: put the earlier format back, never leave half a change
            v4l2_format back;
            std::memset(&back, 0, sizeof back);
            back.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
            back.fmt.pix.width = before.size.width;
            back.fmt.pix.height = before.size.height;
            back.fmt.pix.pixelformat = fourccCode(before.fourcc);
            back.fmt.pix.field = V4L2_FIELD_ANY;
            xioctl(m_fd, VIDIOC_S_FMT, &back);
            return {false, error, QStringLiteral("VIDIOC_S_PARM")};
        }
    }
    return {};
}

QList<Control> V4l2Camera::controls()
{
    QList<Control> result;
    v4l2_query_ext_ctrl q;
    std::memset(&q, 0, sizeof q);
    q.id = V4L2_CTRL_FLAG_NEXT_CTRL | V4L2_CTRL_FLAG_NEXT_COMPOUND;
    while (xioctl(m_fd, VIDIOC_QUERY_EXT_CTRL, &q) == 0) {
        const quint32 nextId = q.id | V4L2_CTRL_FLAG_NEXT_CTRL | V4L2_CTRL_FLAG_NEXT_COMPOUND;
        if (q.type != V4L2_CTRL_TYPE_CTRL_CLASS && !(q.flags & V4L2_CTRL_FLAG_DISABLED)) {
            Control c;
            c.id = q.id;
            c.name = QString::fromLocal8Bit(q.name);
            c.kind = kindOf(q.type);
            c.minimum = q.minimum;
            c.maximum = q.maximum;
            c.step = q.step ? q.step : 1;
            c.defaultValue = q.default_value;
            c.inactive = q.flags & V4L2_CTRL_FLAG_INACTIVE;
            c.readOnly = q.flags & V4L2_CTRL_FLAG_READ_ONLY;
            c.grabbed = q.flags & V4L2_CTRL_FLAG_GRABBED;
            if (c.kind == Control::Other) {
                c.otherKind = otherKindName(q.type);
            } else if (c.kind != Control::Button) {
                v4l2_ext_control ec;
                v4l2_ext_controls ecs;
                std::memset(&ec, 0, sizeof ec);
                std::memset(&ecs, 0, sizeof ecs);
                ec.id = q.id;
                ecs.count = 1;
                ecs.controls = &ec;
                ecs.which = V4L2_CTRL_WHICH_CUR_VAL;
                if (xioctl(m_fd, VIDIOC_G_EXT_CTRLS, &ecs) == 0) {
                    c.value = ec.value;
                }
            }
            if (c.kind == Control::Menu || c.kind == Control::IntegerMenu) {
                for (qint64 i = q.minimum; i <= q.maximum; ++i) {
                    v4l2_querymenu m;
                    std::memset(&m, 0, sizeof m);
                    m.id = q.id;
                    m.index = quint32(i);
                    if (xioctl(m_fd, VIDIOC_QUERYMENU, &m) == 0) {
                        c.menu.append({i, c.kind == Control::Menu ? QString::fromLocal8Bit(reinterpret_cast<const char *>(m.name)) : QString::number(qint64(m.value))});
                    }
                }
            }
            result.append(c);
        }
        q.id = nextId;
    }
    return result;
}

Result V4l2Camera::setControl(quint32 id, qint64 value)
{
    v4l2_ext_control ec;
    v4l2_ext_controls ecs;
    std::memset(&ec, 0, sizeof ec);
    std::memset(&ecs, 0, sizeof ecs);
    ec.id = id;
    ec.value = qint32(value);
    ecs.count = 1;
    ecs.controls = &ec;
    ecs.which = V4L2_CTRL_WHICH_CUR_VAL;
    if (xioctl(m_fd, VIDIOC_S_EXT_CTRLS, &ecs) < 0) {
        return {false, errno, QStringLiteral("VIDIOC_S_EXT_CTRLS")};
    }
    return {};
}

Result V4l2Camera::resetControls(QStringList *failed)
{
    Result overall;
    for (const Control &c : controls()) {
        if (c.kind == Control::Button || c.kind == Control::Other || c.readOnly || c.inactive || c.value == c.defaultValue) {
            continue;
        }
        const Result r = setControl(c.id, c.defaultValue);
        if (!r.ok) {
            overall = r;
            if (failed) {
                failed->append(c.name);
            }
        }
    }
    return overall;
}

QString V4l2Camera::explain(const Result &result, const QString &subject)
{
    switch (result.error) {
    case EBUSY:
        return i18n("Another program is using %1, so it cannot change this now. Close that program and try again.", subject);
    case ERANGE:
    case EINVAL:
        return i18n("%1 does not accept this value. The camera keeps its earlier setting.", subject);
    case EACCES:
    case EPERM:
        return i18n("%1 does not allow this change now. Another setting of the camera may have to change first.", subject);
    case ENODEV:
    case ENOENT:
    case EIO:
        return i18n("%1 is not connected any more. Plug it in again.", subject);
    default:
        return i18n("%1 refused the change (%2).", subject, QString::fromLocal8Bit(std::strerror(result.error)));
    }
}
