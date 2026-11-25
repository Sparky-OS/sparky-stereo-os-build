// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KQuickConfigModule>
#include <QStandardPaths>
#include <QVariantMap>
#include <array>

using namespace Qt::StringLiterals;

namespace
{
const auto configName = u"sparky-stereo-weatherrc"_s;
const auto weatherGroup = u"Weather"_s;

struct Setting {
    QString key;
    QString fallback;
    QStringList choices;
};

const std::array settings{
    Setting{u"Look"_s, u"Auto"_s, {u"Auto"_s, u"IconTheme"_s, u"Vector"_s, u"Photoreal"_s, u"RealWeather"_s}},
    Setting{u"HardwareLook"_s, {}, {QString(), u"Photoreal"_s, u"RealWeather"_s}},
    Setting{u"PanelIcon"_s, u"Colour"_s, {u"Colour"_s, u"OneColour"_s}},
    Setting{u"Shade"_s, u"Present"_s, {u"Present"_s, u"Darker"_s}},
    Setting{u"Animation"_s, u"true"_s, {u"true"_s, u"false"_s}},
};

QString checkedValue(const KConfigGroup &group, const Setting &setting)
{
    const auto value = group.readEntry(setting.key, setting.fallback);
    return setting.choices.contains(value) ? value : setting.fallback;
}
}

class WeatherKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap values READ values NOTIFY changed)
    Q_PROPERTY(QString machineLook READ machineLook NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit WeatherKcm(QObject *parent, const KPluginMetaData &metadata)
        : KQuickConfigModule(parent, metadata)
    {
        setButtons(Apply | Default);
    }

    QVariantMap values() const { return m_values; }
    QString machineLook() const { return m_machineLook; }
    QString error() const { return m_error; }

    Q_INVOKABLE void change(const QString &key, const QString &value)
    {
        for (const auto &setting : settings) {
            if (setting.key != key || !setting.choices.contains(value)) {
                continue;
            }
            m_values[key] = value;
            setNeedsSave(m_reset || m_values != m_loaded);
            Q_EMIT changed();
            return;
        }
    }

    void load() override
    {
        KConfig merged(configName, KConfig::NoGlobals);
        const KConfigGroup active(&merged, weatherGroup);
        KConfig own(userPath(), KConfig::SimpleConfig);
        const KConfigGroup user(&own, weatherGroup);
        for (const auto &setting : settings) {
            m_values[setting.key] = checkedValue(setting.key == u"HardwareLook"_s ? user : active, setting);
        }
        merged.setReadDefaults(true);
        m_machineLook = checkedValue(KConfigGroup(&merged, weatherGroup), settings[1]);
        m_loaded = m_values;
        m_reset = false;
        m_error.clear();
        setNeedsSave(false);
        Q_EMIT changed();
    }

    void defaults() override
    {
        m_values = inheritedDefaults();
        m_values[u"HardwareLook"_s] = QString();
        m_reset = true;
        setNeedsSave(true);
        Q_EMIT changed();
    }

    void save() override
    {
        KConfig own(userPath(), KConfig::SimpleConfig);
        KConfigGroup user(&own, weatherGroup);
        const auto defaults = m_reset ? inheritedDefaults() : QVariantMap();
        for (const auto &setting : settings) {
            const auto value = m_values.value(setting.key).toString();
            if (m_reset || value != m_loaded.value(setting.key).toString()) {
                if (value.isEmpty() || (m_reset && value == defaults.value(setting.key).toString())) {
                    user.revertToDefault(setting.key);
                } else {
                    user.writeEntry(setting.key, value);
                }
            }
        }
        if (!own.sync()) {
            m_error = i18nd("kcm_sparkystereo_weather", "The weather icon settings could not be saved.");
            Q_EMIT changed();
            return;
        }
        load();
    }

Q_SIGNALS:
    void changed();

private:
    static QString userPath()
    {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + u'/' + configName;
    }

    static QVariantMap inheritedDefaults()
    {
        KConfig system(configName, KConfig::NoGlobals);
        system.setReadDefaults(true);
        const KConfigGroup inherited(&system, weatherGroup);
        QVariantMap values;
        for (const auto &setting : settings) {
            values[setting.key] = checkedValue(inherited, setting);
        }
        return values;
    }

    QVariantMap m_values;
    QVariantMap m_loaded;
    QString m_machineLook;
    QString m_error;
    bool m_reset = false;
};

K_PLUGIN_CLASS_WITH_JSON(WeatherKcm, "kcm_sparkystereo_weather.json")
#include "weatherkcm.moc"
