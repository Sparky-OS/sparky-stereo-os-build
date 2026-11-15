/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 * SPDX-License-Identifier: MIT
 *
 * vk-views: one window, one VkSurfaceKHR, and a timed sequence of swapchains with two image layers or one, the way
 * a program that turns its 3D off and on again presents (ORDER 573).
 *
 *   PHASES="2:4,1:4,2:4"   views and seconds per phase; the last phase lasts until the program is stopped
 *   OLD=1                  the next swapchain names the previous one as oldSwapchain (default); OLD=0 destroys the
 *                          previous swapchain first, as a program that releases everything does
 *   X11=1                  an X11 window (xcb) instead of a Wayland one
 *   VK_VENDOR=0x10de       the physical device of that vendor, else the first one
 *   W=800 H=600            the window's size
 *
 * A two-layer swapchain shows layer 0 red and layer 1 blue: each eye one colour. A one-layer swapchain shows its
 * picture's left half green and its right half yellow: a flat window has both halves in each eye, a picture shown as
 * a pair has one colour per eye. Each phase prints what the surface offered and what was made.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <xcb/xcb.h>
#include "xdg-shell-client-protocol.h"

#define VK_USE_PLATFORM_WAYLAND_KHR
#define VK_USE_PLATFORM_XCB_KHR
#include <vulkan/vulkan.h>

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { fprintf(stderr, "%s failed: %d\n", #x, r_); exit(1); } } while (0)

static double start_time;
static double now(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* Wayland */
static struct wl_display *display;
static struct wl_compositor *compositor;
static struct xdg_wm_base *wm_base;
static struct wl_surface *wl_surf;
static struct xdg_surface *xdg_surf;
static struct xdg_toplevel *toplevel;
static bool configured, closed;

static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) { xdg_wm_base_pong(base, serial); }
static const struct xdg_wm_base_listener wm_base_listener = { ping };
static void surface_configure(void *data, struct xdg_surface *s, uint32_t serial)
{
   xdg_surface_ack_configure(s, serial);
   configured = true;
}
static const struct xdg_surface_listener xdg_surface_listener = { surface_configure };
static void top_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s) {}
static void top_close(void *d, struct xdg_toplevel *t) { closed = true; }
static void top_bounds(void *d, struct xdg_toplevel *t, int32_t w, int32_t h) {}
static void top_caps(void *d, struct xdg_toplevel *t, struct wl_array *c) {}
static const struct xdg_toplevel_listener toplevel_listener = { top_configure, top_close, top_bounds, top_caps };
static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version)
{
   if (!strcmp(iface, wl_compositor_interface.name))
      compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
   else if (!strcmp(iface, xdg_wm_base_interface.name)) {
      wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, 1);
      xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
   }
}
static void global_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener registry_listener = { global, global_remove };

/* A Wayland client reads its socket every frame, or the compositor takes it for not responding. */
static void wayland_events(void)
{
   while (wl_display_prepare_read(display) != 0)
      wl_display_dispatch_pending(display);
   wl_display_flush(display);
   struct pollfd fd = { wl_display_get_fd(display), POLLIN, 0 };
   if (poll(&fd, 1, 0) > 0)
      wl_display_read_events(display);
   else
      wl_display_cancel_read(display);
   wl_display_dispatch_pending(display);
}

/* X11 */
static xcb_connection_t *xconn;
static xcb_window_t xwin;
static xcb_atom_t content_atom;

static uint32_t x11_declaration(void)
{
   xcb_get_property_reply_t *r = xcb_get_property_reply(xconn,
      xcb_get_property(xconn, 0, xwin, content_atom, XCB_ATOM_CARDINAL, 0, 1), NULL);
   uint32_t v = r && xcb_get_property_value_length(r) >= 4 ? *(uint32_t *)xcb_get_property_value(r) : 0;
   free(r);
   return v;
}

/* Vulkan */
static VkInstance instance;
static VkPhysicalDevice physical;
static VkDevice device;
static VkQueue queue;
static uint32_t family;
static VkSurfaceKHR surface;
static VkFormat format;
static VkSwapchainKHR swapchain;
static uint32_t image_count, layers;
static VkImage images[8];
static VkSemaphore acquired, rendered[8];
static VkFence fence;
static VkCommandPool pool;
static VkCommandBuffer command;
static VkBuffer staging;
static VkDeviceMemory staging_memory;
static void *staging_map;
static VkExtent2D extent;
static VkDeviceSize staging_size;

static uint32_t host_memory(uint32_t bits)
{
   VkPhysicalDeviceMemoryProperties p;
   vkGetPhysicalDeviceMemoryProperties(physical, &p);
   for (uint32_t i = 0; i < p.memoryTypeCount; i++)
      if ((bits & (1u << i)) && (p.memoryTypes[i].propertyFlags &
          (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) ==
          (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))
         return i;
   fprintf(stderr, "no host-visible memory\n");
   exit(1);
}

static void put(uint8_t *p, uint8_t r, uint8_t g, uint8_t b)
{
   if (format == VK_FORMAT_B8G8R8A8_UNORM || format == VK_FORMAT_B8G8R8A8_SRGB) {
      p[0] = b; p[1] = g; p[2] = r;
   } else {
      p[0] = r; p[1] = g; p[2] = b;
   }
   p[3] = 255;
}

static void fill_staging(void)
{
   const VkDeviceSize need = (VkDeviceSize)extent.width * extent.height * 4 * 2;
   if (need > staging_size) {
      if (staging) {
         vkDestroyBuffer(device, staging, NULL);
         vkUnmapMemory(device, staging_memory);
         vkFreeMemory(device, staging_memory, NULL);
      }
      VkBufferCreateInfo bi = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, NULL, 0, need,
                                VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_SHARING_MODE_EXCLUSIVE, 0, NULL };
      CHECK(vkCreateBuffer(device, &bi, NULL, &staging));
      VkMemoryRequirements req;
      vkGetBufferMemoryRequirements(device, staging, &req);
      VkMemoryAllocateInfo ai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, NULL, req.size, host_memory(req.memoryTypeBits) };
      CHECK(vkAllocateMemory(device, &ai, NULL, &staging_memory));
      CHECK(vkBindBufferMemory(device, staging, staging_memory, 0));
      CHECK(vkMapMemory(device, staging_memory, 0, need, 0, &staging_map));
      staging_size = need;
   }
   uint8_t *p = staging_map;
   for (uint32_t l = 0; l < 2; l++)
      for (uint32_t y = 0; y < extent.height; y++)
         for (uint32_t x = 0; x < extent.width; x++, p += 4) {
            if (layers == 2)
               l == 0 ? put(p, 255, 0, 0) : put(p, 0, 0, 255);
            else
               x < extent.width / 2 ? put(p, 0, 255, 0) : put(p, 255, 255, 0);
         }
}

static void make_swapchain(uint32_t views, bool old)
{
   VkSurfaceCapabilitiesKHR caps;
   CHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &caps));
   layers = views == 2 && caps.maxImageArrayLayers >= 2 ? 2 : 1;
   const int w = getenv("W") ? atoi(getenv("W")) : 800, h = getenv("H") ? atoi(getenv("H")) : 600;
   extent = caps.currentExtent.width != UINT32_MAX ? caps.currentExtent : (VkExtent2D){ (uint32_t)w, (uint32_t)h };
   VkCompositeAlphaFlagBitsKHR alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
   if (!(caps.supportedCompositeAlpha & alpha))
      alpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
   vkDeviceWaitIdle(device);
   VkSwapchainKHR previous = swapchain;
   if (previous && !old) {
      vkDestroySwapchainKHR(device, previous, NULL);
      previous = VK_NULL_HANDLE;
   }
   VkSwapchainCreateInfoKHR ci = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR, .surface = surface,
      .minImageCount = caps.minImageCount < 3 && (caps.maxImageCount == 0 || caps.maxImageCount >= 3) ? 3 : caps.minImageCount,
      .imageFormat = format, .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, .imageExtent = extent,
      .imageArrayLayers = layers,
      .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
      .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE, .preTransform = caps.currentTransform,
      .compositeAlpha = alpha, .presentMode = VK_PRESENT_MODE_FIFO_KHR, .clipped = VK_TRUE,
      .oldSwapchain = previous,
   };
   VkSwapchainKHR made;
   CHECK(vkCreateSwapchainKHR(device, &ci, NULL, &made));
   if (previous)
      vkDestroySwapchainKHR(device, previous, NULL);
   swapchain = made;
   image_count = 8;
   CHECK(vkGetSwapchainImagesKHR(device, swapchain, &image_count, images));
   fill_staging();
   printf("%.2f views %u layers %u maxImageArrayLayers %u extent %ux%u images %u old %d\n", now() - start_time,
          views, layers, caps.maxImageArrayLayers, extent.width, extent.height, image_count, old);
   fflush(stdout);
}

static void frame(void)
{
   uint32_t index;
   CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE, UINT64_MAX));
   VkResult r = vkAcquireNextImageKHR(device, swapchain, UINT64_MAX, acquired, VK_NULL_HANDLE, &index);
   if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) {
      fprintf(stderr, "acquire: %d\n", r);
      exit(1);
   }
   CHECK(vkResetFences(device, 1, &fence));
   CHECK(vkResetCommandBuffer(command, 0));
   VkCommandBufferBeginInfo bi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
   CHECK(vkBeginCommandBuffer(command, &bi));
   VkImageMemoryBarrier b = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
      .image = images[index], .subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, layers },
   };
   vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
   VkBufferImageCopy copies[2];
   for (uint32_t l = 0; l < layers; l++)
      copies[l] = (VkBufferImageCopy){ .bufferOffset = (VkDeviceSize)l * extent.width * extent.height * 4,
                                       .imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, l, 1 },
                                       .imageExtent = { extent.width, extent.height, 1 } };
   vkCmdCopyBufferToImage(command, staging, images[index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, layers, copies);
   b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
   b.dstAccessMask = 0;
   b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
   b.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
   vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &b);
   CHECK(vkEndCommandBuffer(command));
   VkPipelineStageFlags stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
   VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO, NULL, 1, &acquired, &stage, 1, &command, 1, &rendered[index] };
   CHECK(vkQueueSubmit(queue, 1, &si, fence));
   VkPresentInfoKHR pi = { VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, NULL, 1, &rendered[index], 1, &swapchain, &index, NULL };
   r = vkQueuePresentKHR(queue, &pi);
   if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) {
      fprintf(stderr, "present: %d\n", r);
      exit(1);
   }
}

int main(void)
{
   setvbuf(stdout, NULL, _IOLBF, 0);
   start_time = now();
   const bool x11 = getenv("X11") && atoi(getenv("X11"));
   const bool old = !getenv("OLD") || atoi(getenv("OLD"));
   const int w = getenv("W") ? atoi(getenv("W")) : 800, h = getenv("H") ? atoi(getenv("H")) : 600;

   const char *exts[] = { VK_KHR_SURFACE_EXTENSION_NAME,
                          x11 ? VK_KHR_XCB_SURFACE_EXTENSION_NAME : VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME };
   VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL, "vk-views", 1, NULL, 0, VK_API_VERSION_1_1 };
   VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL, 0, &app, 0, NULL, 2, exts };
   CHECK(vkCreateInstance(&ici, NULL, &instance));

   if (x11) {
      xconn = xcb_connect(NULL, NULL);
      if (xcb_connection_has_error(xconn)) { fprintf(stderr, "no X server\n"); return 1; }
      xcb_screen_t *screen = xcb_setup_roots_iterator(xcb_get_setup(xconn)).data;
      xwin = xcb_generate_id(xconn);
      uint32_t values[] = { screen->black_pixel };
      xcb_create_window(xconn, XCB_COPY_FROM_PARENT, xwin, screen->root, 0, 0, w, h, 0,
                        XCB_WINDOW_CLASS_INPUT_OUTPUT, screen->root_visual, XCB_CW_BACK_PIXEL, values);
      xcb_change_property(xconn, XCB_PROP_MODE_REPLACE, xwin, XCB_ATOM_WM_NAME, XCB_ATOM_STRING, 8, 8, "vk-views");
      xcb_map_window(xconn, xwin);
      xcb_flush(xconn);
      xcb_intern_atom_reply_t *a = xcb_intern_atom_reply(xconn,
         xcb_intern_atom(xconn, 0, strlen("_KDE_NET_WM_STEREO_CONTENT"), "_KDE_NET_WM_STEREO_CONTENT"), NULL);
      content_atom = a ? a->atom : XCB_ATOM_NONE;
      free(a);
      VkXcbSurfaceCreateInfoKHR sci = { VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR, NULL, 0, xconn, xwin };
      CHECK(vkCreateXcbSurfaceKHR(instance, &sci, NULL, &surface));
      usleep(300000);
   } else {
      display = wl_display_connect(NULL);
      if (!display) { fprintf(stderr, "no Wayland display\n"); return 1; }
      struct wl_registry *registry = wl_display_get_registry(display);
      wl_registry_add_listener(registry, &registry_listener, NULL);
      wl_display_roundtrip(display);
      wl_surf = wl_compositor_create_surface(compositor);
      xdg_surf = xdg_wm_base_get_xdg_surface(wm_base, wl_surf);
      xdg_surface_add_listener(xdg_surf, &xdg_surface_listener, NULL);
      toplevel = xdg_surface_get_toplevel(xdg_surf);
      xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
      xdg_toplevel_set_title(toplevel, "vk-views");
      xdg_toplevel_set_app_id(toplevel, "vk-views");
      wl_surface_commit(wl_surf);
      while (!configured)
         wl_display_dispatch(display);
      VkWaylandSurfaceCreateInfoKHR sci = { VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR, NULL, 0, display, wl_surf };
      CHECK(vkCreateWaylandSurfaceKHR(instance, &sci, NULL, &surface));
   }

   uint32_t n = 8;
   VkPhysicalDevice devices[8];
   CHECK(vkEnumeratePhysicalDevices(instance, &n, devices));
   const uint32_t vendor = getenv("VK_VENDOR") ? strtoul(getenv("VK_VENDOR"), NULL, 0) : 0;
   physical = devices[0];
   for (uint32_t i = 0; i < n; i++) {
      VkPhysicalDeviceProperties p;
      vkGetPhysicalDeviceProperties(devices[i], &p);
      if (vendor && p.vendorID == vendor) { physical = devices[i]; break; }
   }
   VkPhysicalDeviceProperties props;
   vkGetPhysicalDeviceProperties(physical, &props);
   printf("device %s vendor 0x%x %s\n", props.deviceName, props.vendorID, x11 ? "x11" : "wayland");
   uint32_t qn = 16;
   VkQueueFamilyProperties qf[16];
   vkGetPhysicalDeviceQueueFamilyProperties(physical, &qn, qf);
   family = UINT32_MAX;
   for (uint32_t i = 0; i < qn && family == UINT32_MAX; i++) {
      VkBool32 present = VK_FALSE;
      vkGetPhysicalDeviceSurfaceSupportKHR(physical, i, surface, &present);
      if ((qf[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && present)
         family = i;
   }
   if (family == UINT32_MAX) { fprintf(stderr, "no queue presents to the surface\n"); return 1; }
   const float priority = 1.0f;
   VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, NULL, 0, family, 1, &priority };
   const char *dexts[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
   VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 0, 1, &qci, 0, NULL, 1, dexts, NULL };
   CHECK(vkCreateDevice(physical, &dci, NULL, &device));
   vkGetDeviceQueue(device, family, 0, &queue);

   uint32_t fn = 0;
   CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &fn, NULL));
   VkSurfaceFormatKHR *formats = calloc(fn, sizeof(*formats));
   CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &fn, formats));
   format = formats[0].format;
   for (uint32_t i = 0; i < fn; i++)
      if (formats[i].format == VK_FORMAT_B8G8R8A8_UNORM)
         format = formats[i].format;

   VkSemaphoreCreateInfo semi = { VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
   CHECK(vkCreateSemaphore(device, &semi, NULL, &acquired));
   for (int i = 0; i < 8; i++)
      CHECK(vkCreateSemaphore(device, &semi, NULL, &rendered[i]));
   VkFenceCreateInfo fi = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, NULL, VK_FENCE_CREATE_SIGNALED_BIT };
   CHECK(vkCreateFence(device, &fi, NULL, &fence));
   VkCommandPoolCreateInfo pci = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, NULL,
                                   VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, family };
   CHECK(vkCreateCommandPool(device, &pci, NULL, &pool));
   VkCommandBufferAllocateInfo cai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, NULL, pool,
                                       VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1 };
   CHECK(vkAllocateCommandBuffers(device, &cai, &command));

   char *phases = strdup(getenv("PHASES") ? getenv("PHASES") : "2:4,1:4,2:4");
   char *save = NULL;
   int phase = 0;
   double next_report = 0;
   for (char *item = strtok_r(phases, ",", &save); item; item = strtok_r(NULL, ",", &save), phase++) {
      unsigned views = 0;
      double seconds = 0;
      if (sscanf(item, "%u:%lf", &views, &seconds) < 1) { fprintf(stderr, "bad phase %s\n", item); return 1; }
      const bool last = save == NULL || *save == '\0';
      printf("%.2f phase %d\n", now() - start_time, phase);
      make_swapchain(views, old);
      const double end = now() + seconds;
      while (!closed && (last || now() < end)) {
         frame();
         if (!x11)
            wayland_events();
         else if (now() >= next_report) {
            printf("%.2f x11 declaration %u\n", now() - start_time, x11_declaration());
            next_report = now() + 1.0;
         }
      }
   }
   vkDeviceWaitIdle(device);
   return 0;
}
