// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include <optional>

struct v4l2_query_ext_ctrl;

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

// One mode the camera offers: a pixel format at one size and its highest frame rate there (0 when the driver lists none)
struct ModeCandidate {
    QString fourcc;
    bool compressed = false;
    Size size;
    double fps = 0;
};

// The mode a camera the person has not set starts at (Daniel 2026-11-18, ORDER 682: "the best resolution then best framerate
// in this order of priority"): the largest picture, and at that size the highest frame rate. Ties: the wider picture for two
// sizes of one pixel count, then the format that needs no decoding, then the driver's own order. allowedFormats, when not empty,
// is a known machine's caveat (sparky-stereo-hardware's table): only those formats are considered.
std::optional<Mode> bestMode(const QList<ModeCandidate> &candidates, const QStringList &allowedFormats = {});

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
    bool valueKnown = false; // the driver answered VIDIOC_G_EXT_CTRLS
    quint32 flags = 0; // every V4L2_CTRL_FLAG_* the driver reported (VIDIOC_QUERY_EXT_CTRL)
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

// Whether a control is a setting the page keeps, and if not, why: one rule for the page, the command and the apply step,
// each answer tied to the V4L2 specification (VIDIOC_QUERYCTRL, "Control Flags"; ext-ctrls-camera, the relative and speed
// controls). A setting is kept only while it is active: an inactive one is not changed by the person and not saved.
enum class Keep {
    Setting, // integer with a range, boolean, menu or integer menu that the camera takes and reports
    Button, // V4L2_CTRL_TYPE_BUTTON: an action, no value
    NotEditable, // a kind the page cannot change (64-bit, bitmask, string, compound)
    Payload, // V4L2_CTRL_FLAG_HAS_PAYLOAD or V4L2_CTRL_FLAG_DYNAMIC_ARRAY: arrays, strings, compound values
    ReadOnly, // V4L2_CTRL_FLAG_READ_ONLY: "permanently readable only"
    WriteOnly, // V4L2_CTRL_FLAG_WRITE_ONLY: "typically present for relative controls or action controls"
    Volatile, // V4L2_CTRL_FLAG_VOLATILE: "the value of the control changes continuously"
    Action, // V4L2_CTRL_FLAG_EXECUTE_ON_WRITE: "the control represents an action on the hardware"
    Motion, // a relative or speed control (PAN/TILT/FOCUS/ZOOM/IRIS_RELATIVE, ZOOM_CONTINUOUS, PAN/TILT_SPEED): a movement
    NoRange, // an integer whose maximum is not above its minimum: nothing to set
};
Keep keepRule(const Control &control);
inline bool isSetting(const Control &control)
{
    return keepRule(control) == Keep::Setting;
}
// The rule's answer as a word, for the command's output and the logs
QString keepName(Keep keep);
// The driver's default brought into the control's own range and step, as the driver brings any value it is given (the V4L2
// control framework and uvcvideo both clamp an integer to its range and round it to its step): a default outside the range
// (the A10's camera reports sharpness 0 to 100 with default 120) is otherwise never equal to any value the camera can hold.
qint64 effectiveDefault(const Control &control);

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
    // The errno that ended the last enumeration (formats, controls) or reading of the mode early, 0 when it ended as the API ends
    // a list (EINVAL past the last entry). A device that is going away or still starting answers ENODEV or EIO: an empty list
    // from it is not "this camera has nothing" and is said, never printed as an empty answer.
    int lastError() const { return m_error; }

    QList<Format> formats();
    // The frame rates for one size, as numbers of frames a second; a stepwise range is listed by its limits
    QList<double> frameRates(const QString &fourcc, Size size);
    // Every format and size the camera lists with its highest frame rate there (a stepwise range by its largest size)
    QList<ModeCandidate> modeCandidates();
    Mode currentMode();
    Result setMode(const Mode &mode);

    QList<Control> controls();
    // One control as the driver reports it now (fresh flags: whether it is active changes with its governing control)
    std::optional<Control> control(quint32 id);
    Result setControl(quint32 id, qint64 value);

    // What happened to one value of setControls()
    struct SetOutcome {
        enum State {
            Applied,
            Refused, // the camera answered an error for a setting that is active: a real refusal
            Inactive, // still inactive after every governing control took its value: not set, and not a failure
            Missing, // the camera does not list the control
            NotSetting, // the control is not a setting (keepRule): never set from a saved value
        };
        quint32 id = 0;
        State state = Applied;
        Result result;
        std::optional<Control> control;
    };
    // Sets a group of values the way the API lets a governing control go first, whatever its id: in passes, each control asked
    // for its flags just before it is set (VIDIOC_QUERY_EXT_CTRL), those flagged V4L2_CTRL_FLAG_UPDATE ("changing this control
    // may affect the value of other controls") first in each pass, an inactive one left for the next pass, until a pass sets
    // nothing more. So automatic white balance switched off makes the temperature active before the temperature is set
    // (uvcvideo answers EACCES to a slave set while its master is not in manual mode: uvc_ctrl_is_accessible).
    QList<SetOutcome> setControls(const QList<QPair<quint32, qint64>> &values);
    // Every setting that is active now back to its default (effectiveDefault). A control that becomes inactive while the others
    // are reset (white balance temperature once automatic white balance is back on) keeps the camera's own value: not a failure.
    Result resetControls(QStringList *failed = nullptr);

    static QString fourccText(quint32 code);
    static quint32 fourccCode(const QString &text);
    // The sentence the page shows for a failed ioctl: what happened and what to do (translated)
    static QString explain(const Result &result, const QString &subject);

private:
    Control readControl(const ::v4l2_query_ext_ctrl &q);

    int m_fd = -1;
    int m_openError = 0;
    int m_error = 0;
    QString m_path;
    QString m_card;
    QString m_driver;
    QString m_bus;
    bool m_capture = false;
};
}
