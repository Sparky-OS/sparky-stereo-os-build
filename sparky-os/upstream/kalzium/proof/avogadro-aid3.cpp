/* Test aid for the Kalzium proof (not part of the patches).
 * Kalzium never registers the molecule it loads with Avogadro's layer manager (RWLayerManager::addMolecule), as Avogadro's own application does,
 * so with avogadrolibs 2.0.0 no scene plugin is ever enabled and the molecule viewer stays black (also in Debian's unpatched Kalzium).
 * Before every GLWidget::updateScene() this library registers the molecule and enables "Ball and Stick", so that there is a molecule to measure. */
#include <avogadro/qtgui/molecule.h>
#include <avogadro/qtgui/rwlayermanager.h>
#include <avogadro/qtgui/sceneplugin.h>
#include <avogadro/qtgui/scenepluginmodel.h>
#include <avogadro/qtopengl/glwidget.h>
#include <dlfcn.h>
using namespace Avogadro;
void QtOpenGL::GLWidget::updateScene()
{
    typedef void (*fn)(QtOpenGL::GLWidget *);
    static fn orig = (fn)dlsym(RTLD_NEXT, "_ZN8Avogadro8QtOpenGL8GLWidget11updateSceneEv");
    struct L : QtGui::RWLayerManager { using QtGui::RWLayerManager::addMolecule; };
    static L layers;
    if (molecule()) {
        layers.addMolecule(molecule());
        for (int i = 0; i < sceneModel().rowCount(QModelIndex()); ++i) {
            QModelIndex ix = sceneModel().index(i, 0);
            if (sceneModel().data(ix, Qt::DisplayRole).toString() == QLatin1String("Ball and Stick")) {
                auto *p = qobject_cast<QtGui::ScenePlugin *>(static_cast<QObject *>(ix.internalPointer()));
                if (p && !p->isEnabled()) p->setEnabled(true);
            }
        }
    }
    orig(this);
}
