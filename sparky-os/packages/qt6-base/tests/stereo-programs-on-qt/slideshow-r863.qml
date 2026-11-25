// slideshow-r863.qml -- row 863 part A5: the installer's slideshow (the edition's Calamares branding, show.qml, with
// Calamares' own calamares.slideshow QML module) in a window of its own, without Calamares: nothing is installed or
// changed. It plays the part r863-probe.so plays in a Qt Widgets program:
//  - at every synchronization of the scene (run with QSG_RENDER_LOOP=basic, so it happens on this thread, before the
//    frame is rendered and committed) it logs where the current slide's StereoPicture is in the window, in the format
//    lag.py reads: "R863 flush step=K expect=X,Y expect2=X,Y event=sync";
//  - from 9 s after start it runs the steps start, grow (the window 160x100 larger), next (the next slide), shrink,
//    next, logs "R863 step=K name=STEP expect=X,Y size=WxH margins=3,30 stereoActive=0|1 failure=..." 2.5 s after each,
//    writes R863_OUT/step-K.ready (prog-case.sh captures the screen then; an XMLHttpRequest PUT, allowed by
//    QML_XHR_ALLOW_FILE_WRITE=1) and goes on when prog-case.sh has written step-K.captured (read with a GET, allowed by
//    QML_XHR_ALLOW_FILE_READ=1; 60 s at most, then it says so), and at the end writes R863_OUT/done.
// The margins are the frame Qt draws itself around a window in the rig (3,30, read by the probe in the Widgets rows; QML
// cannot read QWindow::frameMargins). Run: qml -I CALAMARES_QML slideshow-r863.qml -- SHOW_QML OUT_DIR
import QtQuick
import QtQuick.Window

Window {
    id: win
    width: 1280
    height: 760
    visible: true
    title: "r863-slideshow"
    color: "black"

    readonly property var args: Qt.application.arguments
    readonly property string show: args[args.length - 2]
    readonly property string out: args[args.length - 1]
    readonly property var steps: ["grow", "next", "shrink", "next"]
    property int step: 0
    property int phase: 0

    Loader {
        id: loader
        anchors.fill: parent
        source: "file://" + win.show
    }

    function picture() {
        const p = loader.item;
        if (!p || !p.slides || p.slides.length === 0)
            return null;
        const s = p.slides[p.currentSlide];
        for (let i = 0; i < s.children.length; ++i)
            if (s.children[i].stereoActive !== undefined)
                return s.children[i];
        return null;
    }
    function place() {
        const p = picture();
        if (!p)
            return null;
        const q = p.mapToItem(null, 0, 0);
        return { x: Math.round(q.x), y: Math.round(q.y), w: Math.round(p.width), h: Math.round(p.height),
                 active: p.stereoActive, failure: p.stereoFailure };
    }
    onAfterSynchronizing: {
        const q = place();
        if (q)
            console.log("R863 flush step=" + step + " expect=" + q.x + "," + q.y + " expect2=" + q.x + "," + q.y + " event=sync");
    }
    // asks for the file and sets seen when it has content (prog-case.sh writes the step's number into it)
    property bool seen: false
    function look(name) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE && x.responseText.length > 0)
                win.seen = true;
        };
        x.open("GET", "file://" + out + "/" + name);
        x.send();
    }
    property int waited: 0
    Timer {
        id: captured
        interval: 100
        repeat: true
        onTriggered: {
            win.waited += interval;
            const there = win.seen;
            if (!there)
                win.look("step-" + win.step + ".captured");
            if (!there && win.waited < 60000)
                return;
            if (!there)
                console.log("R863 capture timeout step=" + win.step);
            stop();
            win.waited = 0;
            win.seen = false;
            sequence.interval = 200;
            sequence.start();
        }
    }
    function touch(name) {
        const x = new XMLHttpRequest();
        x.open("PUT", "file://" + out + "/" + name);
        x.send(String(step));
    }
    function report(name) {
        const q = place();
        console.log("R863 step=" + step + " name=" + name + " expect=" + (q ? q.x + "," + q.y : "-1,-1") + " window=-1,-1 placed=-1"
                    + " visible=" + (q ? 1 : 0) + " readable=0 size=" + (q ? q.w + "x" + q.h : "0x0") + " margins=3,30 stereoActive="
                    + (q && q.active ? 1 : 0) + " failure=" + (q ? JSON.stringify(q.failure) : "\"no picture\""));
        touch("step-" + step + ".ready");
    }
    function act(name) {
        if (name === "grow") {
            win.width += 160; win.height += 100;
        } else if (name === "shrink") {
            win.width -= 160; win.height -= 100;
        } else if (name === "next") {
            loader.item.goToNextSlide();
        }
    }
    Timer {
        id: sequence
        interval: 9000
        running: true
        onTriggered: {
            // phase 0: report the start; then for each step: act (odd phase), report (even phase)
            if (win.phase === 0) {
                win.report("start");
                win.phase = 1;
                captured.start();
                return;
            } else if (win.phase % 2 === 1) {
                const i = (win.phase - 1) / 2;
                if (i >= win.steps.length) {
                    console.log("R863 result steps=" + win.steps.length + " stale=-1 watched=1");
                    win.touch("done");
                    Qt.callLater(Qt.quit);
                    return;
                }
                win.act(win.steps[i]);
            } else {
                win.step = win.step + 1;
                win.report(win.steps[(win.phase - 2) / 2]);
                win.phase = win.phase + 1;
                captured.start();
                return;
            }
            win.phase = win.phase + 1;
            interval = 2500;
            start();
        }
    }
}
