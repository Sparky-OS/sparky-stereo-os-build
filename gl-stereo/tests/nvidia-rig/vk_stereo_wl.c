#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>

#define VK_USE_PLATFORM_WAYLAND_KHR
#include <vulkan/vulkan.h>
#include <wayland-client.h>
#include "xdg-activation-v1-client-protocol.h"
#include "plasma-window-management-client-protocol.h"
#include "xdg-shell-client-protocol.h"

struct client_state {
   struct wl_display *display;
   struct wl_compositor *compositor;
   struct xdg_wm_base *wm_base;
   struct xdg_activation_v1 *activation;
   struct xdg_activation_token_v1 *activation_token;
   struct org_kde_plasma_window_management *plasma_windows;
   struct xdg_surface *xdg_surface;
   struct xdg_toplevel *toplevel;
   bool configured;
   bool token_ready;
   const char *token_name;
   char window_uuid[64];
   bool window_uuid_ready;
};

static void
check(VkResult result)
{
   if (result != VK_SUCCESS) {
      fprintf(stderr, "Vulkan error %d\n", result);
      abort();
   }
}

static bool
has_extension(const char *name, uint32_t count, VkExtensionProperties *props)
{
   for (uint32_t i = 0; i < count; i++)
      if (!strcmp(name, props[i].extensionName))
         return true;
   return false;
}

static void
registry_global(void *data, struct wl_registry *registry, uint32_t name,
                const char *interface, uint32_t version)
{
   struct client_state *state = data;
   fprintf(stderr, "wayland-global %s v%u\n", interface, version);
   if (!strcmp(interface, wl_compositor_interface.name)) {
      state->compositor = wl_registry_bind(registry, name,
                                           &wl_compositor_interface,
                                           version < 4 ? version : 4);
   } else if (!strcmp(interface, xdg_wm_base_interface.name)) {
      state->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface,
                                        version < 3 ? version : 3);
   } else if (!strcmp(interface, xdg_activation_v1_interface.name)) {
      state->activation = wl_registry_bind(registry, name,
                                           &xdg_activation_v1_interface,
                                           version < 1 ? version : 1);
   } else if (0 && !strcmp(interface, org_kde_plasma_window_management_interface.name)) {
      state->plasma_windows = wl_registry_bind(
         registry, name, &org_kde_plasma_window_management_interface,
         version < 20 ? version : 20);
   }
}

static void
registry_remove(void *data, struct wl_registry *registry, uint32_t name)
{
   (void)data;
   (void)registry;
   (void)name;
}

static const struct wl_registry_listener registry_listener = {
   registry_global,
   registry_remove,
};

static void
wm_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial)
{
   (void)data;
   xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_listener = {
   wm_ping,
};

static void
activation_done(void *data, struct xdg_activation_token_v1 *token,
                const char *token_name)
{
   struct client_state *state = data;
   state->activation_token = token;
   state->token_name = token_name;
   state->token_ready = true;
}

static const struct xdg_activation_token_v1_listener activation_listener = {
   activation_done,
};

static void
plasma_window_with_uuid(void *data,
                        struct org_kde_plasma_window_management *management,
                        uint32_t id, const char *uuid)
{
   struct client_state *state = data;
   (void)management;
   (void)id;
   snprintf(state->window_uuid, sizeof(state->window_uuid), "%s", uuid);
   state->window_uuid_ready = true;
}

static const struct org_kde_plasma_window_management_listener plasma_listener = {
   .window_with_uuid = plasma_window_with_uuid,
};

static void
surface_configure(void *data, struct xdg_surface *surface, uint32_t serial)
{
   struct client_state *state = data;
   xdg_surface_ack_configure(surface, serial);
   state->configured = true;
}

static const struct xdg_surface_listener surface_listener = {
   surface_configure,
};

static void
toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width,
                   int32_t height, struct wl_array *states)
{
   (void)data;
   (void)toplevel;
   (void)width;
   (void)height;
   (void)states;
}

static void
toplevel_close(void *data, struct xdg_toplevel *toplevel)
{
   (void)data;
   (void)toplevel;
}

static const struct xdg_toplevel_listener toplevel_listener = {
   toplevel_configure,
   toplevel_close,
};

int
main(void)
{
   const uint32_t width = 64, height = 32;
   struct client_state state = {0};
   state.display = wl_display_connect(NULL);
   assert(state.display);

   struct wl_registry *registry = wl_display_get_registry(state.display);
   wl_registry_add_listener(registry, &registry_listener, &state);
   assert(wl_display_roundtrip(state.display) >= 0);
   assert(state.compositor && state.wm_base && state.activation);
   if (state.plasma_windows) {
      org_kde_plasma_window_management_add_listener(state.plasma_windows,
                                                     &plasma_listener, &state);
   }
   xdg_wm_base_add_listener(state.wm_base, &wm_listener, &state);

   struct wl_surface *wl_surface = wl_compositor_create_surface(state.compositor);
   assert(wl_surface);
   state.xdg_surface = xdg_wm_base_get_xdg_surface(state.wm_base, wl_surface);
   state.toplevel = xdg_surface_get_toplevel(state.xdg_surface);
   assert(state.xdg_surface && state.toplevel);
   xdg_surface_add_listener(state.xdg_surface, &surface_listener, &state);
   xdg_toplevel_add_listener(state.toplevel, &toplevel_listener, &state);
   xdg_toplevel_set_title(state.toplevel, "Mesa Vulkan stereo Wayland");

   state.activation_token = xdg_activation_v1_get_activation_token(state.activation);
   xdg_activation_token_v1_add_listener(state.activation_token,
                                         &activation_listener, &state);
   xdg_activation_token_v1_set_app_id(state.activation_token,
                                       "mesa-vulkan-stereo-wayland");
   xdg_activation_token_v1_set_surface(state.activation_token, wl_surface);
   xdg_activation_token_v1_commit(state.activation_token);
   assert(wl_display_roundtrip(state.display) >= 0);
   assert(state.token_ready);
   xdg_activation_v1_activate(state.activation, state.token_name, wl_surface);
   xdg_activation_token_v1_destroy(state.activation_token);
   state.activation_token = NULL;
   wl_surface_commit(wl_surface);
   assert(wl_display_roundtrip(state.display) >= 0);
   assert(state.configured);

   uint32_t instance_count = 0;
   check(vkEnumerateInstanceExtensionProperties(NULL, &instance_count, NULL));
   VkExtensionProperties *instance_ext = calloc(instance_count, sizeof(*instance_ext));
   check(vkEnumerateInstanceExtensionProperties(NULL, &instance_count, instance_ext));
   assert(has_extension(VK_KHR_SURFACE_EXTENSION_NAME, instance_count, instance_ext));
   assert(has_extension(VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME, instance_count, instance_ext));
   free(instance_ext);

   const char *instance_extensions[] = {
      VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
   };
   VkApplicationInfo app = {
      .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
      .pApplicationName = "mesa-vulkan-stereo-wayland",
      .apiVersion = VK_API_VERSION_1_1,
   };
   VkInstanceCreateInfo instance_info = {
      .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .pApplicationInfo = &app,
      .enabledExtensionCount = 2,
      .ppEnabledExtensionNames = instance_extensions,
   };
   VkInstance instance;
   check(vkCreateInstance(&instance_info, NULL, &instance));

   VkSurfaceKHR surface;
   VkWaylandSurfaceCreateInfoKHR surface_info = {
      .sType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
      .display = state.display,
      .surface = wl_surface,
   };
   check(vkCreateWaylandSurfaceKHR(instance, &surface_info, NULL, &surface));

   uint32_t physical_count = 0;
   check(vkEnumeratePhysicalDevices(instance, &physical_count, NULL));
   assert(physical_count > 0);
   VkPhysicalDevice *physical_devices = calloc(physical_count, sizeof(*physical_devices));
   check(vkEnumeratePhysicalDevices(instance, &physical_count, physical_devices));
   VkPhysicalDevice physical = physical_devices[0];
   free(physical_devices);

   VkSurfaceCapabilitiesKHR caps;
   check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &caps));
   assert(caps.maxImageArrayLayers == 2);

   uint32_t queue_count = 0;
   vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, NULL);
   VkQueueFamilyProperties *queue_props = calloc(queue_count, sizeof(*queue_props));
   vkGetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, queue_props);
   uint32_t queue_family = UINT32_MAX;
   for (uint32_t i = 0; i < queue_count; i++) {
      VkBool32 present = VK_FALSE;
      check(vkGetPhysicalDeviceSurfaceSupportKHR(physical, i, surface, &present));
      if (present && (queue_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
         queue_family = i;
         break;
      }
   }
   assert(queue_family != UINT32_MAX);
   free(queue_props);

   float priority = 1.0f;
   VkDeviceQueueCreateInfo queue_info = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = queue_family,
      .queueCount = 1,
      .pQueuePriorities = &priority,
   };
   const char *device_extensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
   VkDeviceCreateInfo device_info = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1,
      .pQueueCreateInfos = &queue_info,
      .enabledExtensionCount = 1,
      .ppEnabledExtensionNames = device_extensions,
   };
   VkDevice device;
   check(vkCreateDevice(physical, &device_info, NULL, &device));
   VkQueue queue;
   vkGetDeviceQueue(device, queue_family, 0, &queue);

   VkSwapchainCreateInfoKHR swapchain_info = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
      .surface = surface,
      .minImageCount = 2,
      .imageFormat = VK_FORMAT_B8G8R8A8_UNORM,
      .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
      .imageExtent = {width, height},
      .imageArrayLayers = 2,
      .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
      .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
      .preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
      .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
      .presentMode = VK_PRESENT_MODE_FIFO_KHR,
      .clipped = VK_TRUE,
   };
   VkSwapchainKHR swapchain;
   check(vkCreateSwapchainKHR(device, &swapchain_info, NULL, &swapchain));

   uint32_t image_count = 0;
   check(vkGetSwapchainImagesKHR(device, swapchain, &image_count, NULL));
   assert(image_count >= 2);
   VkImage *images = calloc(image_count, sizeof(*images));
   check(vkGetSwapchainImagesKHR(device, swapchain, &image_count, images));

   VkCommandPoolCreateInfo pool_info = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .queueFamilyIndex = queue_family,
   };
   VkCommandPool pool;
   check(vkCreateCommandPool(device, &pool_info, NULL, &pool));
   VkCommandBufferAllocateInfo alloc_info = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = pool,
      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount = 1,
   };
   VkCommandBuffer command;
   check(vkAllocateCommandBuffers(device, &alloc_info, &command));
   VkSemaphoreCreateInfo semaphore_info = {
      .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
   };
   VkSemaphore acquire, present;
   check(vkCreateSemaphore(device, &semaphore_info, NULL, &acquire));
   check(vkCreateSemaphore(device, &semaphore_info, NULL, &present));
   uint32_t image_index;
   check(vkAcquireNextImageKHR(device, swapchain, UINT64_MAX, acquire,
                               VK_NULL_HANDLE, &image_index));

   VkCommandBufferBeginInfo begin = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
   };
   check(vkBeginCommandBuffer(command, &begin));
   VkImageMemoryBarrier barrier = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
      .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
      .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
      .image = images[image_index],
      .subresourceRange = {
         .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
         .levelCount = 1,
         .layerCount = 2,
      },
   };
   vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                        VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL,
                        1, &barrier);
   bool swap_eyes = getenv("VULKAN_STEREO_SWAP_EYES") != NULL;
   VkClearColorValue colors[2] = {
      swap_eyes ? (VkClearColorValue){{0, 1, 0, 1}} : (VkClearColorValue){{1, 0, 0, 1}},
      swap_eyes ? (VkClearColorValue){{1, 0, 0, 1}} : (VkClearColorValue){{0, 1, 0, 1}},
   };
   for (uint32_t layer = 0; layer < 2; layer++)
      vkCmdClearColorImage(command, images[image_index],
                           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &colors[layer],
                           1, &(VkImageSubresourceRange) {
                              VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, layer, 1 });
   barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
   barrier.dstAccessMask = 0;
   barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
   barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
   vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT,
                        VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0,
                        NULL, 1, &barrier);
   check(vkEndCommandBuffer(command));

   VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
   VkSubmitInfo submit = {
      .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .waitSemaphoreCount = 1,
      .pWaitSemaphores = &acquire,
      .pWaitDstStageMask = &wait_stage,
      .commandBufferCount = 1,
      .pCommandBuffers = &command,
      .signalSemaphoreCount = 1,
      .pSignalSemaphores = &present,
   };
   check(vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE));
   VkPresentInfoKHR present_info = {
      .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
      .waitSemaphoreCount = 1,
      .pWaitSemaphores = &present,
      .swapchainCount = 1,
      .pSwapchains = &swapchain,
      .pImageIndices = &image_index,
   };
   check(vkQueuePresentKHR(queue, &present_info));
   check(vkQueueWaitIdle(queue));
   assert(wl_display_roundtrip(state.display) >= 0);
   if (state.window_uuid_ready) {
      printf("window_uuid=%s\n", state.window_uuid);
      fflush(stdout);
   }
   const char *hold = getenv("VULKAN_STEREO_HOLD_SECONDS");
   if (hold) {
      unsigned long secs = strtoul(hold, NULL, 10);
      if (getenv("VK_READ_SOCKET")) {
         /* a Wayland client reads its socket: the driver's explicit sync and fifo events arrive there */
         for (unsigned long i = 0; i < secs * 20; ++i) {
            while (wl_display_prepare_read(state.display) != 0)
               wl_display_dispatch_pending(state.display);
            wl_display_flush(state.display);
            struct pollfd pfd = { .fd = wl_display_get_fd(state.display), .events = POLLIN };
            if (poll(&pfd, 1, 50) > 0)
               wl_display_read_events(state.display);
            else
               wl_display_cancel_read(state.display);
            wl_display_dispatch_pending(state.display);
         }
      } else
         sleep(secs);
   }

   puts(swap_eyes ? "PASS: Vulkan Wayland stereo deliberate eye swap" :
        "PASS: Vulkan Wayland stereo layers and packed present");
   vkDestroySemaphore(device, present, NULL);
   vkDestroySemaphore(device, acquire, NULL);
   vkDestroyCommandPool(device, pool, NULL);
   free(images);
   vkDestroySwapchainKHR(device, swapchain, NULL);
   vkDestroyDevice(device, NULL);
   vkDestroySurfaceKHR(instance, surface, NULL);
   vkDestroyInstance(instance, NULL);
   xdg_toplevel_destroy(state.toplevel);
   xdg_surface_destroy(state.xdg_surface);
   wl_surface_destroy(wl_surface);
   xdg_wm_base_destroy(state.wm_base);
   xdg_activation_v1_destroy(state.activation);
   if (state.plasma_windows)
      org_kde_plasma_window_management_destroy(state.plasma_windows);
   wl_compositor_destroy(state.compositor);
   wl_registry_destroy(registry);
   wl_display_disconnect(state.display);
   return 0;
}
