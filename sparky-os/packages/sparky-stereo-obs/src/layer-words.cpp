/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
// The words the stereo layer shares with every program ("Enable 3D", "3D Input Format", each packing, "Swap left and
// right eyes", "Display Settings…") come from the layer's own catalogue, context Stereo::FileChoiceMenu, so OBS says
// them as Dolphin, Gwenview and the players do: one name per idea, translated once.
#include "layer-words.hpp"

#include <obs-module.h>

#include <QCoreApplication>
#include <QFile>
#include <QTranslator>

namespace SparkyStereo {

static QString layerLanguage()
{
	// OBS names its languages "pt-BR", "de-DE"; the layer's catalogues are pt_BR, zh_CN, zh_TW and the bare language
	const QString locale = QString::fromUtf8(obs_get_locale()).replace(QLatin1Char('-'), QLatin1Char('_'));
	if (locale == QLatin1String("pt_BR") || locale == QLatin1String("zh_CN") || locale == QLatin1String("zh_TW"))
		return locale;
	return locale.section(QLatin1Char('_'), 0, 0);
}

QString layerWord(const char *text)
{
	static bool tried = false;
	if (!tried) {
		tried = true;
		const QString path = QStringLiteral("/usr/share/locale/%1/LC_MESSAGES/stereo-layer_qt.qm").arg(layerLanguage());
		auto *candidate = new QTranslator(QCoreApplication::instance());
		if (QFile::exists(path) && candidate->load(path)) {
			QCoreApplication::installTranslator(candidate);
		} else {
			delete candidate;
			if (layerLanguage() != QLatin1String("en"))
				blog(LOG_INFO, "[sparky-stereo-obs] the stereo layer has no catalogue at %s: its words stay in English",
				     path.toUtf8().constData());
		}
	}
	return QCoreApplication::translate("Stereo::FileChoiceMenu", text);
}

} // namespace SparkyStereo
