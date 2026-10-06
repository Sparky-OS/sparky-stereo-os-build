/* Test aid: print the scene's radius/centre and the active scene plugins after every GLWidget::updateScene() */
#include <avogadro/qtgui/molecule.h>
#include <avogadro/qtopengl/glwidget.h>
#include <avogadro/qtgui/scenepluginmodel.h>
#include <avogadro/qtgui/sceneplugin.h>
#include <avogadro/rendering/glrenderer.h>
#include <avogadro/rendering/camera.h>
#include <dlfcn.h>
#include <stdio.h>
using namespace Avogadro;
void QtOpenGL::GLWidget::updateScene()
{
    typedef void (*fn)(QtOpenGL::GLWidget *);
    static fn orig = (fn)dlsym(RTLD_NEXT, "_ZN8Avogadro8QtOpenGL8GLWidget11updateSceneEv");
    orig(this);
    auto &r = renderer();
    int active = sceneModel().activeScenePlugins().size();
    fprintf(stderr, "aid2: updateScene: active plugins %d, scene radius %g centre %g %g %g, mol atoms %d\n", active, r.scene().radius(), r.scene().center()[0], r.scene().center()[1], r.scene().center()[2], molecule() ? (int)molecule()->atomCount() : -1);
    for (int i = 0; i < sceneModel().rowCount(QModelIndex()); ++i) { auto ix = sceneModel().index(i, 0); fprintf(stderr, "aid2:   plugin %d: %s checked=%d\n", i, sceneModel().data(ix, Qt::DisplayRole).toString().toUtf8().constData(), sceneModel().data(ix, Qt::CheckStateRole).toInt()); }
    auto m = r.camera().modelView().matrix();
    fprintf(stderr, "aid2: modelView t = %g %g %g\n", m(0,3), m(1,3), m(2,3));
}
