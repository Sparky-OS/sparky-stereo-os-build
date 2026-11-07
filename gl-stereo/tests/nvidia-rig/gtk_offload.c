/* A GtkGLArea under a GtkGraphicsOffload: the case that died on zink over NVIDIA's Vulkan (ORDER 457). Draws green. */
#include <gtk/gtk.h>
#include <epoxy/gl.h>
static gboolean render(GtkGLArea *a, GdkGLContext *c, gpointer d) { glClearColor(0, 1, 0, 1); glClear(GL_COLOR_BUFFER_BIT); return TRUE; }
static gboolean tick(gpointer w) { gtk_widget_queue_draw(w); return G_SOURCE_CONTINUE; }
static void activate(GtkApplication *app, gpointer d)
{
  GtkWidget *win = gtk_application_window_new(app);
  gtk_window_set_default_size(GTK_WINDOW(win), 400, 300);
  GtkWidget *area = gtk_gl_area_new();
  g_signal_connect(area, "render", G_CALLBACK(render), NULL);
  GtkWidget *off = gtk_graphics_offload_new(area);
  gtk_graphics_offload_set_enabled(GTK_GRAPHICS_OFFLOAD(off), GTK_GRAPHICS_OFFLOAD_ENABLED);
  gtk_window_set_child(GTK_WINDOW(win), off);
  gtk_window_present(GTK_WINDOW(win));
  g_timeout_add(100, tick, area);
  printf("RESULT gtk offload window shown\n"); fflush(stdout);
}
int main(int argc, char **argv)
{
  GtkApplication *app = gtk_application_new("org.sparky.offloadtest", G_APPLICATION_NON_UNIQUE);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  return g_application_run(G_APPLICATION(app), 1, argv);
}
