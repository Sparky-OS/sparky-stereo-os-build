#!/usr/bin/env python3
"""Opaque test clients; only KWin supplies their window translucency."""
import os
from pathlib import Path
from PySide6.QtCore import QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QApplication, QWidget, QDialog


def paint(widget):
    painter = QPainter(widget)
    painter.fillRect(widget.rect(), QColor("#a0a0a0"))
    painter.setPen(QColor("#202020"))
    painter.drawText(30, 45, widget.windowTitle())


class Normal(QWidget):
    def paintEvent(self, event):
        paint(self)


class Dialog(QDialog):
    def paintEvent(self, event):
        paint(self)


app = QApplication([])
windows = []
for cls, title in ((Normal, "Inactive 91%"), (Dialog, "Dialog 91%"), (Normal, "Active opaque")):
    window = cls()
    window.setWindowTitle(title)
    window.resize(400, 300)
    window.show()
    windows.append(window)
fullscreen = Normal()
fullscreen.setWindowTitle("Fullscreen opaque")
command = Path(os.environ["HOME"]) / "fullscreen-request"
timer = QTimer()
timer.timeout.connect(lambda: fullscreen.showFullScreen() if command.exists() and not fullscreen.isVisible() else None)
timer.start(200)
app.exec()
