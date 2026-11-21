// SPDX-License-Identifier: BSD-3-Clause
// A QVTKOpenGLStereoWidget in Crystal Eyes stereo draws a turning cone for 60 frames; VTK's warnings
// "Error in cache state for GL_DRAW_BUFFER" are counted through the output window's WarningEvent.
// Exit 0: a stereo context and no such warning; 1: warnings (the count is printed); 77: the window got no
// stereo context, so nothing was tested.
#include <QApplication>
#include <QOpenGLContext>
#include <QSurfaceFormat>
#include <QTimer>

#include <QVTKOpenGLStereoWidget.h>
#include <QVTKOpenGLWindow.h>
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
int DrawBufferWarnings = 0;
void CountWarning(vtkObject*, unsigned long, void*, void* callData)
{
  const char* text = static_cast<const char*>(callData);
  if (text && std::strstr(text, "Error in cache state for GL_DRAW_BUFFER"))
  {
    ++DrawBufferWarnings;
  }
}
}

int main(int argc, char* argv[])
{
  QSurfaceFormat::setDefaultFormat(QVTKRenderWindowAdapter::defaultFormat(/*stereo_capable=*/false));
  QApplication app(argc, argv);

  vtkNew<vtkCallbackCommand> counter;
  counter->SetCallback(CountWarning);
  vtkOutputWindow::GetInstance()->AddObserver(vtkCommand::WarningEvent, counter);

  QVTKOpenGLStereoWidget widget;
  widget.setFormat(QVTKRenderWindowAdapter::defaultFormat(/*stereo_capable=*/true));
  vtkNew<vtkGenericOpenGLRenderWindow> window;
  window->SetStereoCapableWindow(1);
  window->SetStereoTypeToCrystalEyes();
  window->SetStereoRender(1);
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

  QOpenGLContext* context = widget.embeddedOpenGLWindow()->context();
  const bool stereo = context && context->format().stereo();
  std::cout << "stereo context: " << (stereo ? "yes" : "no") << "\nframes: " << frames
            << "\nGL_DRAW_BUFFER warnings: " << DrawBufferWarnings << std::endl;
  if (!stereo)
  {
    return 77;
  }
  return DrawBufferWarnings == 0 ? 0 : 1;
}
