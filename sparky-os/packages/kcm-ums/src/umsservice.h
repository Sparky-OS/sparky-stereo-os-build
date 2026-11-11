/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

/** The ums.service user unit, driven through systemctl (UMS_KCM_SYSTEMCTL replaces the program in tests). */
class UmsService
{
public:
    bool isEnabled() const;
    bool isActive() const;
    bool setEnabled(bool enabled);
    bool restartIfActive();

    QString errorString() const;

private:
    bool run(const QStringList &arguments, QString *output = nullptr) const;

    mutable QString m_error;
};
