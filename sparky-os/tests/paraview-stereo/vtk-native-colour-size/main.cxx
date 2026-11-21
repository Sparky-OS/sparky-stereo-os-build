// SPDX-License-Identifier: BSD-3-Clause
// A mono QVTKOpenGLNativeWidget (the widget ParaView's flat views use) draws a turning cone for 60 frames; VTK's
// warnings "Failed to get <red|green|blue|alpha> color buffer size" are counted through the output window's WarningEvent.
// Exit 0: no such warning; 1: warnings (the count is printed). The render window's alpha bit planes are printed too.
#include <QApplication>
#include <QGuiApplication>
#include <QSurfaceFormat>
#include <QTimer>

#include <QVTKOpenGLNativeWidget.h>
#include <QVTKRenderWindowAdapter.h>
#include <vtkActor.h>
#include <vtkCallbackCommand.h>
#include <vtkCamera.h>
#include <vtkCommand.h>
#include <vtkConeSource.h>
#include <vtkGenericOpenGLRenderWindow.h>
#include <vtkNew.h>
#include <vtkOutputWindow.h>
#include <vtkPolyDataMapper.h>
#include <vtkRenderer.h>

#include <cstring>
#include <iostream>

namespace
{
int ColourSizeWarnings = 0;
void CountWarning(vtkObject*, unsigned long, void*, void* callData)
{
  const char* text = static_cast<const char*>(callData);
  if (text && std::strstr(text, "color buffer size"))
  {
    ++ColourSizeWarnings;
  }
}
}

int main(int argc, char* argv[])
{
  QSurfaceFormat::setDefaultFormat(QVTKOpenGLNativeWidget::defaultFormat());
  QApplication app(argc, argv);

  vtkNew<vtkCallbackCommand> counter;
  counter->SetCallback(CountWarning);
  vtkOutputWindow::GetInstance()->AddObserver(vtkCommand::WarningEvent, counter);

  QVTKOpenGLNativeWidget widget;
  vtkNew<vtkGenericOpenGLRenderWindow> window;
  widget.setRenderWindow(window);

  vtkNew<vtkConeSource> cone;
  vtkNew<vtkPolyDataMapper> mapper;
  mapper->SetInputConnection(cone->GetOutputPort());
  vtkNew<vtkActor> actor;
  actor->SetMapper(mapper);
  vtkNew<vtkRenderer> renderer;
  renderer->AddActor(actor);
  window->AddRenderer(renderer);

  widget.resize(640, 480);
  widget.show();

  int frames = 0;
  QTimer timer;
  QObject::connect(&timer, &QTimer::timeout,
    [&]()
    {
      renderer->GetActiveCamera()->Azimuth(3);
      window->Render();
      if (++frames == 60)
      {
        app.quit();
      }
    });
  timer.start(30);
  app.exec();

  std::cout << "platform: " << QGuiApplication::platformName().toStdString() << "\nframes: " << frames
            << "\nalpha bit planes: " << window->GetAlphaBitPlanes()
            << "\ncolor buffer size warnings: " << ColourSizeWarnings << std::endl;
  return ColourSizeWarnings == 0 ? 0 : 1;
}
