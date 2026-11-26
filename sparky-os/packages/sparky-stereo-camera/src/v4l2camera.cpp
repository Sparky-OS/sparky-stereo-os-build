// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "v4l2camera.h"

#include <KLocalizedString>
#include <QSet>
#include <QtGlobal>

#include <algorithm>
#include <cerrno>
#include <cmath>
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

// The controls the specification describes as a movement, not a position (ext-ctrls-camera.rst): the relative ones "turn" or
// "move" by an amount and are "write-only"; ZOOM_CONTINUOUS and PAN/TILT_SPEED move at a speed until stopped. A saved value of
// one of them would move the camera again at every plug-in.
bool isMotion(quint32 id)
{
    switch (id) {
    case V4L2_CID_PAN_RELATIVE:
    case V4L2_CID_TILT_RELATIVE:
    case V4L2_CID_FOCUS_RELATIVE:
    case V4L2_CID_ZOOM_RELATIVE:
    case V4L2_CID_IRIS_RELATIVE:
    case V4L2_CID_ZOOM_CONTINUOUS:
    case V4L2_CID_PAN_SPEED:
    case V4L2_CID_TILT_SPEED:
        return true;
    default:
        return false;
    }
}
}

Keep Sparky::Camera::keepRule(const Control &c)
{
    if (c.kind == Control::Button) {
        return Keep::Button;
    }
    if (c.flags & (V4L2_CTRL_FLAG_HAS_PAYLOAD | V4L2_CTRL_FLAG_DYNAMIC_ARRAY)) {
        return Keep::Payload;
    }
    if (c.kind == Control::Other) {
        return Keep::NotEditable;
    }
    if (c.readOnly || (c.flags & V4L2_CTRL_FLAG_READ_ONLY)) {
        return Keep::ReadOnly;
    }
    if (isMotion(c.id)) {
        return Keep::Motion;
    }
    if (c.flags & V4L2_CTRL_FLAG_WRITE_ONLY) {
        return Keep::WriteOnly;
    }
    // An auto cluster in automatic mode marks its manual controls "inactive and volatile" (driver-api v4l2-controls, "Handling
    // autogain/gain-type Controls with Auto Clusters"), and clears both in manual mode: such a control is a setting that waits
    // for its governing control. Only a control that is volatile while active changes by itself as a matter of course.
    if ((c.flags & V4L2_CTRL_FLAG_VOLATILE) && !(c.flags & V4L2_CTRL_FLAG_INACTIVE) && !c.inactive) {
        return Keep::Volatile;
    }
    if (c.flags & V4L2_CTRL_FLAG_EXECUTE_ON_WRITE) {
        return Keep::Action;
    }
    if (c.kind == Control::Integer && c.maximum <= c.minimum) {
        return Keep::NoRange;
    }
    return Keep::Setting;
}

QString Sparky::Camera::keepName(Keep keep)
{
    switch (keep) {
    case Keep::Setting:
        return QStringLiteral("setting");
    case Keep::Button:
        return QStringLiteral("button");
    case Keep::NotEditable:
        return QStringLiteral("not-editable");
    case Keep::Payload:
        return QStringLiteral("payload");
    case Keep::ReadOnly:
        return QStringLiteral("read-only");
    case Keep::WriteOnly:
        return QStringLiteral("write-only");
    case Keep::Volatile:
        return QStringLiteral("volatile");
    case Keep::Action:
        return QStringLiteral("action");
    case Keep::Motion:
        return QStringLiteral("motion");
    case Keep::NoRange:
        return QStringLiteral("no-range");
    }
    return {};
}

qint64 Sparky::Camera::effectiveDefault(const Control &c)
{
    if (c.kind == Control::Boolean) {
        return std::clamp<qint64>(c.defaultValue, 0, 1);
    }
    if (c.kind != Control::Integer || c.maximum <= c.minimum) {
        return c.defaultValue;
    }
    const qint64 v = qBound(c.minimum, c.defaultValue, c.maximum);
    if (v == c.maximum) {
        return v;
    }
    const qint64 step = c.step > 0 ? c.step : 1;
    const qint64 rounded = c.minimum + (v - c.minimum + step / 2) / step * step;
    return qMin(rounded, c.maximum);
}

std::optional<Mode> Sparky::Camera::bestMode(const QList<ModeCandidate> &candidates, const QStringList &allowedFormats)
{
    // a is better than b: the larger picture, the wider one, the faster one, the one that needs no decoding; else the first listed
    const auto better = [](const ModeCandidate &a, const ModeCandidate &b) {
        const qint64 pa = qint64(a.size.width) * a.size.height;
        const qint64 pb = qint64(b.size.width) * b.size.height;
        if (pa != pb) {
            return pa > pb;
        }
        if (a.size.width != b.size.width) {
            return a.size.width > b.size.width;
        }
        if (std::abs(a.fps - b.fps) > 0.01) {
            return a.fps > b.fps;
        }
        return !a.compressed && b.compressed;
    };
    const ModeCandidate *best = nullptr;
    for (const ModeCandidate &c : candidates) {
        if (c.size.width <= 0 || c.size.height <= 0 || (!allowedFormats.isEmpty() && !allowedFormats.contains(c.fourcc))) {
            continue;
        }
        if (!best || better(c, *best)) {
            best = &c;
        }
    }
    if (!best) {
        return std::nullopt;
    }
    return Mode{best->fourcc, best->size, best->fps};
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
    m_error = 0;
    for (quint32 i = 0;; ++i) {
        v4l2_fmtdesc d;
        std::memset(&d, 0, sizeof d);
        d.index = i;
        d.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (xioctl(m_fd, VIDIOC_ENUM_FMT, &d) < 0) {
            // EINVAL past the last format is the end of the list (VIDIOC_ENUM_FMT); anything else is the device not answering
            if (errno != EINVAL) {
                m_error = errno;
            }
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

QList<ModeCandidate> V4l2Camera::modeCandidates()
{
    QList<ModeCandidate> result;
    for (const Format &f : formats()) {
        for (const SizeEntry &s : f.sizes) {
            ModeCandidate c{f.fourcc, f.compressed, s.stepwise ? s.max : s.size, 0};
            for (double r : frameRates(f.fourcc, c.size)) {
                c.fps = std::max(c.fps, r);
            }
            result.append(c);
        }
    }
    return result;
}

Mode V4l2Camera::currentMode()
{
    Mode mode;
    m_error = 0;
    v4l2_format f;
    std::memset(&f, 0, sizeof f);
    f.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(m_fd, VIDIOC_G_FMT, &f) == 0) {
        mode.fourcc = fourccText(f.fmt.pix.pixelformat);
        mode.size = {int(f.fmt.pix.width), int(f.fmt.pix.height)};
    } else {
        m_error = errno;
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

Control V4l2Camera::readControl(const ::v4l2_query_ext_ctrl &q)
{
    Control c;
    c.id = q.id;
    c.name = QString::fromLocal8Bit(q.name);
    c.kind = kindOf(q.type);
    c.minimum = q.minimum;
    c.maximum = q.maximum;
    c.step = q.step ? q.step : 1;
    c.defaultValue = q.default_value;
    c.flags = q.flags;
    c.inactive = q.flags & V4L2_CTRL_FLAG_INACTIVE;
    c.readOnly = q.flags & V4L2_CTRL_FLAG_READ_ONLY;
    c.grabbed = q.flags & V4L2_CTRL_FLAG_GRABBED;
    if (c.kind == Control::Other) {
        c.otherKind = otherKindName(q.type);
    } else if (c.kind != Control::Button && !(q.flags & V4L2_CTRL_FLAG_WRITE_ONLY)) {
        // a write-only control has no value to read: the driver answers EACCES (VIDIOC_QUERYCTRL, V4L2_CTRL_FLAG_WRITE_ONLY)
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
            c.valueKnown = true;
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
    return c;
}

QList<Control> V4l2Camera::controls()
{
    QList<Control> result;
    v4l2_query_ext_ctrl q;
    std::memset(&q, 0, sizeof q);
    q.id = V4L2_CTRL_FLAG_NEXT_CTRL | V4L2_CTRL_FLAG_NEXT_COMPOUND;
    m_error = 0;
    while (true) {
        if (xioctl(m_fd, VIDIOC_QUERY_EXT_CTRL, &q) < 0) {
            // EINVAL after the last control is the end of the list (VIDIOC_QUERYCTRL); anything else is the device not answering
            if (errno != EINVAL) {
                m_error = errno;
            }
            break;
        }
        const quint32 nextId = q.id | V4L2_CTRL_FLAG_NEXT_CTRL | V4L2_CTRL_FLAG_NEXT_COMPOUND;
        // DISABLED: "permanently disabled and should be ignored by the application"
        if (q.type != V4L2_CTRL_TYPE_CTRL_CLASS && !(q.flags & V4L2_CTRL_FLAG_DISABLED)) {
            result.append(readControl(q));
        }
        q.id = nextId;
    }
    return result;
}

std::optional<Control> V4l2Camera::control(quint32 id)
{
    v4l2_query_ext_ctrl q;
    std::memset(&q, 0, sizeof q);
    q.id = id;
    if (xioctl(m_fd, VIDIOC_QUERY_EXT_CTRL, &q) < 0 || q.type == V4L2_CTRL_TYPE_CTRL_CLASS || (q.flags & V4L2_CTRL_FLAG_DISABLED)) {
        return std::nullopt;
    }
    return readControl(q);
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

QList<V4l2Camera::SetOutcome> V4l2Camera::setControls(const QList<QPair<quint32, qint64>> &values)
{
    QList<SetOutcome> done;
    QList<QPair<quint32, qint64>> pending = values;
    QSet<quint32> update;
    for (const Control &c : controls()) {
        if (c.flags & V4L2_CTRL_FLAG_UPDATE) {
            update.insert(c.id);
        }
    }
    std::stable_sort(pending.begin(), pending.end(), [&update](const auto &a, const auto &b) {
        const bool ua = update.contains(a.first);
        const bool ub = update.contains(b.first);
        return ua != ub ? ua : a.first < b.first;
    });
    for (bool progress = true; progress && !pending.isEmpty();) {
        progress = false;
        for (auto it = pending.begin(); it != pending.end();) {
            SetOutcome o;
            o.id = it->first;
            o.control = control(it->first);
            if (!o.control) {
                o.state = SetOutcome::Missing;
            } else if (!isSetting(*o.control)) {
                o.state = SetOutcome::NotSetting;
            } else if (o.control->inactive) {
                ++it;
                continue;
            } else {
                o.result = setControl(it->first, it->second);
                o.state = o.result.ok ? SetOutcome::Applied : SetOutcome::Refused;
            }
            done.append(o);
            it = pending.erase(it);
            progress = true;
        }
    }
    for (const auto &[id, value] : std::as_const(pending)) {
        Q_UNUSED(value)
        SetOutcome o;
        o.id = id;
        o.state = SetOutcome::Inactive;
        o.control = control(id);
        done.append(o);
    }
    return done;
}

Result V4l2Camera::resetControls(QStringList *failed)
{
    QList<QPair<quint32, qint64>> values;
    for (const Control &c : controls()) {
        if (isSetting(c) && !c.inactive && c.valueKnown && c.value != effectiveDefault(c)) {
            values.append({c.id, effectiveDefault(c)});
        }
    }
    Result overall;
    for (const SetOutcome &o : setControls(values)) {
        if (o.state == SetOutcome::Refused) {
            overall = o.result;
            if (failed) {
                failed->append(o.control ? o.control->name : QString::number(o.id));
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
