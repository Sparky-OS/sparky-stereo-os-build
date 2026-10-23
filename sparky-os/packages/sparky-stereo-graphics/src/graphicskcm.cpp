#include "graphicskcm.h"
#include <KPluginFactory>
K_PLUGIN_CLASS_WITH_JSON(GraphicsKcm, "kcm_sparkystereo_graphics.json")
GraphicsKcm::GraphicsKcm(QObject *parent, const KPluginMetaData &data) : KQuickConfigModule(parent, data) {}
#include "graphicskcm.moc"
