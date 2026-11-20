/* ORDER 768 reproducer: what geoclue 2.8.2 does at start, in a dozen lines.
 *
 * gclue_web_source_constructed() calls g_network_monitor_can_reach_async(); a moment later
 * gclue_static_source's check_monitor() calls g_file_new_for_path() on the main thread.
 * With GLib 2.90.1's GNetworkMonitorNetlink, can_reach_async() builds the proxy enumerator on a
 * pool thread; with the slow resolver module that thread holds default_modules_lock while the
 * main thread takes the GOnce of g_vfs_get_default(), and each waits for the other.
 *
 * Build: gcc -o repro repro.c $(pkg-config --cflags --libs gio-2.0)
 * Run:   GIO_EXTRA_MODULES=DIR GIO_USE_PROXY_RESOLVER=g768-slow GIO_USE_NETWORK_MONITOR=netlink \
 *        GIO_USE_VFS=local timeout 20 ./repro
 * Exit:  0 when the main thread got its GFile and the check finished; 124 (from timeout) when it hung.
 */
#include <gio/gio.h>

static void
reach_done (GObject      *source,
            GAsyncResult *result,
            gpointer      user_data)
{
  GError *error = NULL;
  gboolean reachable = g_network_monitor_can_reach_finish (G_NETWORK_MONITOR (source), result, &error);

  g_print ("can_reach finished: %s%s\n", reachable ? "reachable" : "not reachable: ",
           error ? error->message : "");
  g_clear_error (&error);
  g_main_loop_quit (user_data);
}

int
main (void)
{
  GMainLoop *loop = g_main_loop_new (NULL, FALSE);
  GNetworkMonitor *monitor = g_network_monitor_get_default ();
  GSocketConnectable *address = g_network_address_parse_uri ("https://g768.invalid/", 443, NULL);
  GFile *file;

  g_print ("network monitor: %s\n", G_OBJECT_TYPE_NAME (monitor));
  g_network_monitor_can_reach_async (monitor, address, NULL, reach_done, loop);
  g_usleep (G_USEC_PER_SEC / 10);

  file = g_file_new_for_path ("/etc/geolocation");
  g_print ("g_file_new_for_path returned on the main thread\n");
  g_object_unref (file);

  g_main_loop_run (loop);
  g_object_unref (address);
  g_main_loop_unref (loop);
  return 0;
}
