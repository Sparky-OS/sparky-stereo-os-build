/* A GIO proxy resolver module for the ORDER 768 reproducer.
 *
 * Its construction does what libproxy's config-sysconfig plugin does inside glib-networking's
 * GLibproxyResolver: it makes a GFile (so it needs g_vfs_get_default()), after a pause that lets
 * the application reach g_vfs_get_default() first. GIO constructs the default resolver inside
 * _g_io_module_get_default(), with default_modules_lock held.
 *
 * Build: gcc -shared -fPIC -o libg768slowproxy.so slowproxy.c $(pkg-config --cflags --libs gio-2.0)
 * Use:   GIO_EXTRA_MODULES=DIR GIO_USE_PROXY_RESOLVER=g768-slow
 */
#include <gio/gio.h>

typedef struct { GObject parent; } G768SlowProxy;
typedef struct { GObjectClass parent_class; } G768SlowProxyClass;

static void g768_slow_proxy_iface_init (GProxyResolverInterface *iface);

G_DEFINE_DYNAMIC_TYPE_EXTENDED (G768SlowProxy, g768_slow_proxy, G_TYPE_OBJECT, 0,
                                G_IMPLEMENT_INTERFACE_DYNAMIC (G_TYPE_PROXY_RESOLVER,
                                                               g768_slow_proxy_iface_init))

static void
g768_slow_proxy_init (G768SlowProxy *self)
{
  GFile *file;

  g_usleep (G_USEC_PER_SEC / 2);
  file = g_file_new_for_path ("/etc/sysconfig/proxy");
  g_object_unref (file);
}

static void
g768_slow_proxy_class_init (G768SlowProxyClass *klass)
{
}

static void
g768_slow_proxy_class_finalize (G768SlowProxyClass *klass)
{
}

static gboolean
g768_slow_proxy_is_supported (GProxyResolver *resolver)
{
  return TRUE;
}

static gchar **
g768_slow_proxy_lookup (GProxyResolver  *resolver,
                        const gchar     *uri,
                        GCancellable    *cancellable,
                        GError         **error)
{
  gchar **proxies = g_new0 (gchar *, 2);

  proxies[0] = g_strdup ("direct://");
  return proxies;
}

static void
g768_slow_proxy_lookup_async (GProxyResolver      *resolver,
                              const gchar         *uri,
                              GCancellable        *cancellable,
                              GAsyncReadyCallback  callback,
                              gpointer             user_data)
{
  GTask *task = g_task_new (resolver, cancellable, callback, user_data);

  g_task_return_pointer (task, g768_slow_proxy_lookup (resolver, uri, cancellable, NULL),
                         (GDestroyNotify) g_strfreev);
  g_object_unref (task);
}

static gchar **
g768_slow_proxy_lookup_finish (GProxyResolver  *resolver,
                               GAsyncResult    *result,
                               GError         **error)
{
  return g_task_propagate_pointer (G_TASK (result), error);
}

static void
g768_slow_proxy_iface_init (GProxyResolverInterface *iface)
{
  iface->is_supported = g768_slow_proxy_is_supported;
  iface->lookup = g768_slow_proxy_lookup;
  iface->lookup_async = g768_slow_proxy_lookup_async;
  iface->lookup_finish = g768_slow_proxy_lookup_finish;
}

G_MODULE_EXPORT void
g_io_module_load (GIOModule *module)
{
  g_type_module_use (G_TYPE_MODULE (module));
  g768_slow_proxy_register_type (G_TYPE_MODULE (module));
  g_io_extension_point_implement (G_PROXY_RESOLVER_EXTENSION_POINT_NAME,
                                  g768_slow_proxy_get_type (), "g768-slow", 0);
}

G_MODULE_EXPORT void
g_io_module_unload (GIOModule *module)
{
}
