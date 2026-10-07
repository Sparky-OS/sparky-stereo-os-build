// Test aid: an ordinary Qt widgets window that never asks for stereo (2D control).
#include <QApplication>
#include <QLabel>
#include <QPushButton>
#include <QTimer>
#include <QVBoxLayout>
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QWidget w;
    w.setFixedSize(240, 120);
    w.setStyleSheet("background:#204060");
    auto *l = new QVBoxLayout(&w);
    auto *a = new QLabel("plain widgets");
    a->setStyleSheet("color:#ffffff;background:#a02020");
    auto *b = new QPushButton("button");
    l->addWidget(a);
    l->addWidget(b);
    w.show();
    QTimer::singleShot(qEnvironmentVariableIntValue("QT_STEREO_HOLD_MS") ?: 12000, &app, &QApplication::quit);
    return app.exec();
}
