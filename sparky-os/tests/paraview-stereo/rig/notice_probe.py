#!/usr/bin/env python3
"""notice_probe.py EARLY|LATE|GL|GL-ORPHAN|GL-REOPEN: a QMainWindow and a window-modal QMessageBox (open()) parented to it, the box opened before
the main window is shown (EARLY: a zero timer queued before show(), the way a ParaView view queues its notice during start-up)
or once the main window is exposed (LATE); GL: LATE, then a QOpenGLWidget added to the main window 2 s after the box
opened (the first render-to-texture widget makes Qt recreate the top-level's platform window); GL-ORPHAN: the same with a
box that has no parent; GL-REOPEN: GL with the edition's notice logic (pqStereoEditionNotice.h): the main window's
platform surface watched; a box still open 0.3 s after its destruction is closed, and a box closed within 3 s of it
is opened again over the new window. Prints when the box gets a close
event. Exits after 12 s."""
import sys
from PyQt6.QtCore import QDateTime, QEvent, QObject, QTimer
from PyQt6.QtGui import QPlatformSurfaceEvent
from PyQt6.QtOpenGLWidgets import QOpenGLWidget
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox

app = QApplication(sys.argv[:1])
main = QMainWindow(); main.setWindowTitle("probe main"); main.resize(600, 400)


class Box(QMessageBox):
    def closeEvent(self, e):
        print("box closeEvent", flush=True); super().closeEvent(e)


class Watch(QObject):
    lost_at = 0

    def eventFilter(self, obj, ev):
        if ev.type() == QEvent.Type.PlatformSurface and \
                ev.surfaceEventType() == QPlatformSurfaceEvent.SurfaceEventType.SurfaceAboutToBeDestroyed:
            self.lost_at = QDateTime.currentMSecsSinceEpoch(); print("main surface about to be destroyed", flush=True)
            dialog = self.parent()
            QTimer.singleShot(300, lambda: dialog.close() if dialog.isVisible() else None)  # xcb keeps it, below
        return False


def open_box():
    global box, watch
    box = Box(QMessageBox.Icon.Information, "probe notice", "probe notice text", QMessageBox.StandardButton.Ok,
              None if sys.argv[1] == "GL-ORPHAN" else main)
    if sys.argv[1] == "GL-REOPEN":
        watch = Watch(box)
        main.windowHandle().installEventFilter(watch)

        def finished(_):
            if watch.lost_at and QDateTime.currentMSecsSinceEpoch() - watch.lost_at < 3000:
                print("closed with the main window's surface: open again", flush=True)
                QTimer.singleShot(250, open_box)
        box.finished.connect(finished)
    box.open(); print("box opened; main visible:", main.isVisible(), flush=True)


def add_gl():
    main.setCentralWidget(QOpenGLWidget()); print("QOpenGLWidget added", flush=True)


if sys.argv[1] == "EARLY":
    QTimer.singleShot(0, open_box)
    QTimer.singleShot(1000, main.show)
else:
    main.show()
    QTimer.singleShot(2000, open_box)
    if sys.argv[1].startswith("GL"):
        QTimer.singleShot(4000, add_gl)
QTimer.singleShot(12000, app.quit)
app.exec()
