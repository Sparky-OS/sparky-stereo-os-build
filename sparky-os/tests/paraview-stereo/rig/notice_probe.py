#!/usr/bin/env python3
"""notice_probe.py EARLY|LATE: a QMainWindow and a window-modal QMessageBox (open()) parented to it, the box opened before
the main window is shown (EARLY: a zero timer queued before show(), the way a ParaView view queues its notice during start-up)
or once the main window is exposed (LATE). Prints when the box gets a close event. Exits after 12 s."""
import sys
from PyQt6.QtCore import QTimer
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox

app = QApplication(sys.argv[:1])
main = QMainWindow(); main.setWindowTitle("probe main"); main.resize(600, 400)


class Box(QMessageBox):
    def closeEvent(self, e):
        print("box closeEvent", flush=True); super().closeEvent(e)


def open_box():
    box = Box(QMessageBox.Icon.Information, "probe notice", "probe notice text", QMessageBox.StandardButton.Ok, main)
    box.open(); print("box opened; main visible:", main.isVisible(), flush=True)


if sys.argv[1] == "EARLY":
    QTimer.singleShot(0, open_box)
    QTimer.singleShot(1000, main.show)
else:
    main.show()
    QTimer.singleShot(2000, open_box)
QTimer.singleShot(12000, app.quit)
app.exec()
