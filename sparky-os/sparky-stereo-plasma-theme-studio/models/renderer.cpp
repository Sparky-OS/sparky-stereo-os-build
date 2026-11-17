// SPDX-License-Identifier: GPL-2.0-or-later
#include "camera.h"
#include "drawing.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <vtkActor.h>
#include <vtkActorCollection.h>
#include <vtkAssembly.h>
#include <vtkCamera.h>
#include <vtkEGLRenderWindow.h>
#include <vtkGLTFImporter.h>
#include <vtkImageData.h>
#include <vtkLight.h>
#include <vtkNew.h>
#include <vtkRenderer.h>
#include <vtkWindowToImageFilter.h>
#include <vtkVersion.h>
#include <iostream>

int main(int argc,char **argv)
{
    QCoreApplication app(argc,argv);
    if(argc!=11) return 2;
    try {
        const QString path=QString::fromLocal8Bit(argv[1]),out=QString::fromLocal8Bit(argv[2]);
        const int n=QString(argv[3]).toInt(),output=QString(argv[7]).toInt(),presentation=QString(argv[8]).toInt();
        const double value=QString(argv[4]).toDouble();
        const Depth::Limits limits{QString(argv[5]).toDouble(),QString(argv[6]).toDouble()};
        const bool flat=QString(argv[9]).toInt();
        if(n<8 || n>2048 || value < -1 || value>1 || !QFileInfo(path).isReadable()) throw std::runtime_error("unreadable-model");
        vtkNew<vtkEGLRenderWindow> window;
        window->SetOffScreenRendering(1);window->SetSize(n,n);window->SetMultiSamples(0);window->SetAlphaBitPlanes(1);
        vtkNew<vtkRenderer> renderer;window->AddRenderer(renderer);renderer->SetBackground(0,0,0);renderer->SetBackgroundAlpha(0);renderer->AutomaticLightCreationOff();
        vtkNew<vtkGLTFImporter> importer;importer->SetRenderWindow(window);importer->SetFileName(path.toUtf8().constData());
        if(!importer->Update()) throw std::runtime_error("unreadable-model");
        double bounds[6];renderer->ComputeVisiblePropBounds(bounds);
        const auto camera=ModelCamera::fit(bounds,n,value,limits,output,presentation,flat);
        vtkNew<vtkAssembly> scene;
        auto *actors=renderer->GetActors();actors->InitTraversal();
        QList<vtkActor*> parts;while(auto *actor=actors->GetNextActor()) parts<<actor;
        if(parts.isEmpty()) throw std::runtime_error("empty-model");
        for(auto *actor:parts) {scene->AddPart(actor);renderer->RemoveActor(actor);}
        scene->SetPosition(0,0,camera.translation);renderer->AddActor(scene);
        const double cx=(bounds[0]+bounds[1])/2,cy=(bounds[2]+bounds[3])/2,cz=(bounds[4]+bounds[5])/2;
        vtkNew<vtkLight> light;light->SetLightTypeToSceneLight();light->SetPosition(cx-camera.distance,cy+camera.distance,cz+camera.distance);light->SetFocalPoint(cx,cy,cz);renderer->AddLight(light);
        QDir().mkpath(out);
        QImage views[2];
        for(int eye=0;eye<2;++eye) {
            const double x=(eye?1:-1)*camera.separation/2;
            vtkNew<vtkCamera> view;
            view->SetPosition(cx+x,cy,cz+camera.distance);view->SetFocalPoint(cx+x,cy,cz);view->SetViewUp(0,1,0);
            view->SetViewAngle(2*std::atan(n/(2*camera.focalPixels))*180/std::acos(-1.));
            view->SetWindowCenter(-2*camera.focalPixels*x/(n*camera.distance),0);
            view->SetClippingRange(camera.distance/10,camera.distance*2);
            renderer->SetActiveCamera(view);window->Render();
            if(!window->SupportsOpenGL()) throw std::runtime_error("renderer-unavailable");
            vtkNew<vtkWindowToImageFilter> grab;grab->SetInput(window);grab->SetInputBufferTypeToRGBA();grab->ReadFrontBufferOff();grab->ShouldRerenderOff();grab->Update();
            auto *pixels=static_cast<unsigned char*>(grab->GetOutput()->GetScalarPointer());
            views[eye]=QImage(pixels,n,n,n*4,QImage::Format_RGBA8888).flipped(Qt::Vertical).copy();
            if(!views[eye].save(out+(eye?"/right.png":"/left.png"))) throw std::runtime_error("write-error");
        }
        if(QString(argv[10]).toInt()) savePns(out+"/pair.pns",views[0],views[1]);
        auto result=camera.json();result["bounds"]=QJsonArray{bounds[0],bounds[1],bounds[2],bounds[3],bounds[4],bounds[5]};
        result["vtk"]=vtkVersion::GetVTKVersion();result["capabilities"]=QString::fromUtf8(window->ReportCapabilities());
        std::cout<<QJsonDocument(result).toJson(QJsonDocument::Compact).constData()<<'\n';
        return 0;
    }catch(const std::exception &e) {std::cerr<<e.what()<<'\n';return 1;}
}
