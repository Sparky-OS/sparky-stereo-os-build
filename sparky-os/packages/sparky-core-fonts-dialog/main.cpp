// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
#include <DebconfGui.h>
#include <QApplication>
#include <QCloseEvent>
#include <QDebug>
#include <QHBoxLayout>
#include <QPushButton>
#include <QRadioButton>
#include <QTextEdit>
#include <QTimer>

// Keep KDE's debconf renderer and protocol. Only the EULA actions differ from
// its generic boolean's OK/Cancel radio buttons. Debconf alone stores consent.
class Licence : public DebconfKde::DebconfGui
{
public:
    explicit Licence(const QString &socket) : DebconfGui(socket)
    {
        auto actions = new QHBoxLayout;
        decline = new QPushButton(qEnvironmentVariable("CORE_FONTS_DECLINE"), this);
        accept = new QPushButton(qEnvironmentVariable("CORE_FONTS_ACCEPT"), this);
        decline->setObjectName("declineLicence");
        accept->setObjectName("acceptLicence");
        actions->addStretch();
        actions->addWidget(decline);
        actions->addWidget(accept);
        qobject_cast<QVBoxLayout *>(layout())->addLayout(actions);
        connect(decline, &QPushButton::clicked, this, [this] { answer(false); });
        connect(accept, &QPushButton::clicked, this, [this] { answer(true); });
        connect(this, &DebconfGui::activated, this, [this] {
            yes = findChild<QRadioButton *>("radioButtonYes");
            no = findChild<QRadioButton *>("radioButtonNo");
            const bool question = yes && no;
            decline->setVisible(question);
            accept->setVisible(question);
            if (auto next = findChild<QPushButton *>("nextPB")) {
                next->setVisible(!question);
                next->setDefault(!question);
                if (!question) next->setFocus();
            }
            setWindowTitle(qEnvironmentVariable("CORE_FONTS_TITLE"));
            qInfo() << "core-fonts: KDE debconf" << (question ? "EULA" : "note")
                    << "platform=" << QGuiApplication::platformName()
                    << "accepted=" << (question && yes->isChecked());
            if (question) {
                yes->hide();
                no->hide();
                decline->setDefault(true);
                decline->setFocus();
            }
            // KDE's note text is itself scrollable; keep the actions visible.
            for (auto text : findChildren<QTextEdit *>()) text->setMinimumHeight(280);
            resize(760, 650);
            show();
            raise();
        });
        connect(this, &DebconfGui::deactivated, this, &QWidget::hide);
        hide();
    }
protected:
    void closeEvent(QCloseEvent *event) override
    {
        if (yes && no) {
            // Closing is an actual negative answer, including after focusing
            // Accept. Do not disconnect and let debconf fall back to a terminal.
            answer(false);
            event->ignore();
        } else {
            DebconfGui::closeEvent(event);
        }
    }
private:
    void answer(bool accepted)
    {
        if (!yes || !no) return;
        (accepted ? yes : no)->setChecked(true);
        QMetaObject::invokeMethod(this, "on_nextPB_clicked", Qt::DirectConnection);
        yes = nullptr;
        no = nullptr;
        hide();
    }
    QRadioButton *yes = nullptr;
    QRadioButton *no = nullptr;
    QPushButton *decline;
    QPushButton *accept;
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    if (argc != 2 || qEnvironmentVariableIsEmpty("CORE_FONTS_ACCEPT") ||
        qEnvironmentVariableIsEmpty("CORE_FONTS_DECLINE")) return 2;
    Licence licence(QString::fromLocal8Bit(argv[1]));
    return app.exec();
}
