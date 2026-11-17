// SPDX-License-Identifier: GPL-2.0-or-later
#include "camera.h"
#include "drawing.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QtEndian>
#include <cstring>
#include <iostream>
#include <vtkActor.h>
#include <vtkActorCollection.h>
#include <vtkAssembly.h>
#include <vtkCamera.h>
#include <vtkEGLRenderWindow.h>
#include <vtkGLTFImporter.h>
#include <vtkImageData.h>
#include <vtkLight.h>
#include <vtkLightCollection.h>
#include <vtkMemoryResourceStream.h>
#include <vtkNew.h>
#include <vtkRenderer.h>
#include <vtkURILoader.h>
#include <vtkVersion.h>
#include <vtkWindowToImageFilter.h>

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 11)
        return 2;
    try {
        const QString path = QString::fromLocal8Bit(argv[1]), out = QString::fromLocal8Bit(argv[2]);
        const int n = QString(argv[3]).toInt(), output = QString(argv[7]).toInt(),
                  presentation = QString(argv[8]).toInt();
        const double value = QString(argv[4]).toDouble();
        const Depth::Limits limits { QString(argv[5]).toDouble(), QString(argv[6]).toDouble() };
        const bool flat = QString(argv[9]).toInt();
        if (n < 8 || n > 2048 || value < -1 || value > 1 || !QFileInfo(path).isReadable())
            throw std::runtime_error("unreadable-model");
        vtkNew<vtkEGLRenderWindow> window;
        window->SetOffScreenRendering(1);
        window->SetSize(n, n);
        window->SetMultiSamples(0);
        window->SetAlphaBitPlanes(1);
        vtkNew<vtkRenderer> renderer;
        window->AddRenderer(renderer);
        renderer->SetBackground(0, 0, 0);
        renderer->SetBackgroundAlpha(0);
        renderer->AutomaticLightCreationOff();
        vtkNew<vtkGLTFImporter> importer;
        importer->SetRenderWindow(window);
        importer->SetFileName(path.toUtf8().constData());
        if (path.endsWith(".glb", Qt::CaseInsensitive)) {
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly))
                throw std::runtime_error("unreadable-model");
            const auto container = file.readAll();
            if (container.size() < 12 || container.left(4) != "glTF"
                || qFromLittleEndian<quint32>(container.constData() + 4) != 2
                || qFromLittleEndian<quint32>(container.constData() + 8) != quint64(container.size()))
                throw std::runtime_error("unreadable-model");
            QByteArray json;
            bool binary = false;
            for (qsizetype offset = 12; offset < container.size();) {
                if (offset + 8 > container.size())
                    throw std::runtime_error("unreadable-model");
                const auto length = qFromLittleEndian<quint32>(container.constData() + offset);
                if (length > quint64(container.size() - offset - 8) || length % 4 != 0)
                    throw std::runtime_error("unreadable-model");
                const auto type = container.mid(offset + 4, 4);
                if (offset == 12 && type != "JSON")
                    throw std::runtime_error("unreadable-model");
                if (type == "JSON")
                    json = container.mid(offset + 8, length);
                if (type == QByteArray("BIN\0", 4))
                    binary = true;
                offset += 8 + length;
            }
            // The GLB BIN chunk is optional. VTK's file path assumes it exists;
            // its public JSON stream path resolves the same external resources without that assumption.
            if (!binary) {
                vtkNew<vtkMemoryResourceStream> stream;
                stream->SetBuffer(json.constData(), json.size(), true);
                vtkNew<vtkURILoader> resources;
                if (!resources->SetBaseFileName(path.toStdString()))
                    throw std::runtime_error("unreadable-model");
                importer->SetStream(stream);
                importer->SetStreamURILoader(resources);
                importer->StreamIsBinaryOff();
            }
        }
        if (!importer->Update())
            throw std::runtime_error("unreadable-model");
        double bounds[6];
        renderer->ComputeVisiblePropBounds(bounds);
        const auto camera = ModelCamera::fit(bounds, n, value, limits, output, presentation, flat);
        vtkNew<vtkAssembly> scene;
        auto* actors = renderer->GetActors();
        actors->InitTraversal();
        QList<vtkActor*> parts;
        while (auto* actor = actors->GetNextActor())
            parts << actor;
        if (parts.isEmpty())
            throw std::runtime_error("empty-model");
        for (auto* actor : parts) {
            scene->AddPart(actor);
            renderer->RemoveActor(actor);
        }
        scene->SetPosition(0, 0, camera.translation);
        renderer->AddActor(scene);
        const double cx = (bounds[0] + bounds[1]) / 2, cy = (bounds[2] + bounds[3]) / 2,
                     cz = (bounds[4] + bounds[5]) / 2;
        auto* lights = renderer->GetLights();
        lights->InitTraversal();
        while (auto* sourceLight = lights->GetNextItem()) {
            double position[3], focal[3];
            sourceLight->GetPosition(position);
            sourceLight->GetFocalPoint(focal);
            sourceLight->SetPosition(position[0], position[1], position[2] + camera.translation);
            sourceLight->SetFocalPoint(focal[0], focal[1], focal[2] + camera.translation);
        }
        if (lights->GetNumberOfItems() == 0) {
            vtkNew<vtkLight> light;
            light->SetLightTypeToSceneLight();
            light->SetPosition(cx - camera.distance, cy + camera.distance, cz + camera.distance);
            light->SetFocalPoint(cx, cy, cz);
            renderer->AddLight(light);
        }
        QDir().mkpath(out);
        QImage views[2];
        for (int eye = 0; eye < 2; ++eye) {
            const double x = (eye ? 1 : -1) * camera.separation / 2;
            vtkNew<vtkCamera> view;
            view->SetPosition(cx + x, cy, cz + camera.distance);
            view->SetFocalPoint(cx + x, cy, cz);
            view->SetViewUp(0, 1, 0);
            view->SetViewAngle(2 * std::atan(n / (2 * camera.focalPixels)) * 180 / std::acos(-1.));
            view->SetWindowCenter(-2 * camera.focalPixels * x / (n * camera.distance), 0);
            view->SetClippingRange(camera.distance / 10, camera.distance * 2);
            renderer->SetActiveCamera(view);
            window->Render();
            if (!window->SupportsOpenGL())
                throw std::runtime_error("renderer-unavailable");
            vtkNew<vtkWindowToImageFilter> grab;
            grab->SetInput(window);
            grab->SetInputBufferTypeToRGBA();
            grab->ReadFrontBufferOff();
            grab->ShouldRerenderOff();
            grab->Update();
            auto* pixels = static_cast<unsigned char*>(grab->GetOutput()->GetScalarPointer());
            views[eye] = QImage(n, n, QImage::Format_RGBA8888);
            for (int y = 0; y < n; ++y)
                std::memcpy(views[eye].scanLine(y), pixels + (n - 1 - y) * n * 4, n * 4);
            if (!views[eye].save(out + (eye ? "/right.png" : "/left.png")))
                throw std::runtime_error("write-error");
        }
        if (QString(argv[10]).toInt())
            savePns(out + "/pair.pns", views[0], views[1]);
        auto result = camera.json();
        result["bounds"] = QJsonArray { bounds[0], bounds[1], bounds[2], bounds[3], bounds[4], bounds[5] };
        result["vtk"] = vtkVersion::GetVTKVersion();
        result["capabilities"] = QString::fromUtf8(window->ReportCapabilities());
        std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
