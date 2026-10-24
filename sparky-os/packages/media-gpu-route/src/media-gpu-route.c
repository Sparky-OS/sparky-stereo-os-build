/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysmacros.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <xf86drm.h>

static int has_extension(const VkExtensionProperties *extensions, uint32_t count, const char *name)
{
    for (uint32_t i = 0; i < count; i++)
        if (!strcmp(extensions[i].extensionName, name))
            return 1;
    return 0;
}

/* An instance with the window system surfaces of the session, so that Mesa's
 * device selection orders the GPUs as it does for the renderer. */
static VkInstance create_instance(void)
{
    uint32_t count = 0;
    if (vkEnumerateInstanceExtensionProperties(NULL, &count, NULL) != VK_SUCCESS)
        return VK_NULL_HANDLE;
    VkExtensionProperties *extensions = calloc(count ? count : 1, sizeof(*extensions));
    if (!extensions)
        return VK_NULL_HANDLE;
    if (vkEnumerateInstanceExtensionProperties(NULL, &count, extensions) != VK_SUCCESS) {
        free(extensions);
        return VK_NULL_HANDLE;
    }
    const char *enabled[3];
    uint32_t num_enabled = 0;
    if (has_extension(extensions, count, "VK_KHR_surface")) {
        enabled[num_enabled++] = "VK_KHR_surface";
        if (getenv("WAYLAND_DISPLAY") && has_extension(extensions, count, "VK_KHR_wayland_surface"))
            enabled[num_enabled++] = "VK_KHR_wayland_surface";
        if (getenv("DISPLAY") && has_extension(extensions, count, "VK_KHR_xcb_surface"))
            enabled[num_enabled++] = "VK_KHR_xcb_surface";
    }
    free(extensions);
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "media-gpu-route", .apiVersion = VK_API_VERSION_1_2 };
    VkInstanceCreateInfo create = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app, .enabledExtensionCount = num_enabled, .ppEnabledExtensionNames = enabled };
    VkInstance instance;
    if (vkCreateInstance(&create, NULL, &instance) != VK_SUCCESS)
        return VK_NULL_HANDLE;
    return instance;
}

/* The hardware GPUs in the loader's order, with their render nodes; with
 * devices_out, the matching Vulkan physical devices too. */
static int list_routes(VkInstance instance, struct media_gpu_route **out, VkPhysicalDevice **devices_out)
{
    *out = NULL;
    if (devices_out)
        *devices_out = NULL;
    uint32_t count = 0;
    VkPhysicalDevice *devices = NULL;
    struct media_gpu_route *routes = NULL;
    VkPhysicalDevice *found_devices = NULL;
    int found = 0;
    if (vkEnumeratePhysicalDevices(instance, &count, NULL) != VK_SUCCESS || !count)
        goto done;
    devices = calloc(count, sizeof(*devices));
    routes = calloc(count, sizeof(*routes));
    found_devices = calloc(count, sizeof(*found_devices));
    if (!devices || !routes || !found_devices || vkEnumeratePhysicalDevices(instance, &count, devices) != VK_SUCCESS)
        goto done;
    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceDrmPropertiesEXT drm = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT };
        VkPhysicalDeviceProperties2 properties = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &drm };
        vkGetPhysicalDeviceProperties2(devices[i], &properties);
        if (properties.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU || !drm.hasRender)
            continue;
        drmDevicePtr device = NULL;
        dev_t id = makedev(drm.renderMajor, drm.renderMinor);
        if (drmGetDeviceFromDevId(id, 0, &device))
            continue;
        const char *node = device->available_nodes & (1 << DRM_NODE_RENDER) ? device->nodes[DRM_NODE_RENDER] : NULL;
        if (node && !access(node, R_OK | W_OK)) {
            found_devices[found] = devices[i];
            struct media_gpu_route *route = &routes[found++];
            route->vendor_id = properties.properties.vendorID;
            route->device_id = properties.properties.deviceID;
            route->drm_device = id;
            snprintf(route->render_node, sizeof(route->render_node), "%s", node);
            snprintf(route->name, sizeof(route->name), "%s", properties.properties.deviceName);
        }
        drmFreeDevice(&device);
    }
done:
    free(devices);
    if (!found) {
        free(routes);
        free(found_devices);
        return 0;
    }
    *out = routes;
    if (devices_out)
        *devices_out = found_devices;
    else
        free(found_devices);
    return found;
}

int media_gpu_routes(struct media_gpu_route **out)
{
    *out = NULL;
    VkInstance instance = create_instance();
    if (instance == VK_NULL_HANDLE)
        return 0;
    int found = list_routes(instance, out, NULL);
    vkDestroyInstance(instance, NULL);
    return found;
}

int media_gpu_route_default(struct media_gpu_route *route)
{
    if (!route)
        return 0;
    memset(route, 0, sizeof(*route));
    struct media_gpu_route *routes = NULL;
    int count = media_gpu_routes(&routes);
    if (count)
        *route = routes[0];
    free(routes);
    return count > 0;
}

int media_gpu_route_vulkan_import(const struct media_gpu_route *gpu)
{
    if (!gpu)
        return -1;
    VkInstance instance = create_instance();
    if (instance == VK_NULL_HANDLE)
        return -1;
    struct media_gpu_route *routes = NULL;
    VkPhysicalDevice *devices = NULL;
    int count = list_routes(instance, &routes, &devices);
    int result = -1;
    for (int i = 0; i < count; i++) {
        if (routes[i].drm_device != gpu->drm_device)
            continue;
        uint32_t num = 0;
        VkExtensionProperties *extensions = NULL;
        if (vkEnumerateDeviceExtensionProperties(devices[i], NULL, &num, NULL) == VK_SUCCESS
            && (extensions = calloc(num ? num : 1, sizeof(*extensions)))
            && vkEnumerateDeviceExtensionProperties(devices[i], NULL, &num, extensions) == VK_SUCCESS)
            result = has_extension(extensions, num, VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME)
                && has_extension(extensions, num, VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME);
        free(extensions);
        break;
    }
    free(routes);
    free(devices);
    vkDestroyInstance(instance, NULL);
    return result;
}

/* Where players draw is the person's choice on the Graphics page (sparky-stereo-graphics): its command names
 * the render node players use now (the choice, or Automatic: the GPU measured best on the machine). A caller
 * that copies its pictures back decodes there first, every other GPU behind it in order, so a source it cannot
 * decode still falls back. A caller that imports decoded surfaces keeps the graphics stack's order, because its
 * renderer draws on the GPU the program was started on, and the page's launch environment puts it there.
 * Nothing is written. A GPU chosen at launch (DRI_PRIME, a Vulkan device selection, an NVIDIA offload) is
 * more specific than the page and wins; a missing, failing or unknown answer changes nothing. */
static char graphics_page_node[128];
static pthread_once_t graphics_page_once = PTHREAD_ONCE_INIT;

static void ask_graphics_page(void)
{
    static const char *const launch_choice[] = { "DRI_PRIME", "MESA_VK_DEVICE_SELECT", "VK_LOADER_DRIVERS_SELECT", "__NV_PRIME_RENDER_OFFLOAD" };
    for (size_t i = 0; i < sizeof(launch_choice) / sizeof(launch_choice[0]); i++)
        if (getenv(launch_choice[i]))
            return;
    FILE *answer = popen("sparky-stereo-gpu-env --category players --print render-node 2>/dev/null", "re");
    if (!answer)
        return;
    char node[sizeof(graphics_page_node)] = "";
    if (!fgets(node, sizeof(node), answer))
        node[0] = '\0';
    if (pclose(answer) != 0)
        return;
    node[strcspn(node, "\n")] = '\0';
    memcpy(graphics_page_node, node, sizeof(node));
}

void media_gpu_route_prefer_graphics_page(struct media_gpu_route *routes, int count)
{
    if (count < 2)
        return;
    pthread_once(&graphics_page_once, ask_graphics_page);
    if (!graphics_page_node[0])
        return;
    for (int i = 1; i < count; i++) {
        if (strcmp(routes[i].render_node, graphics_page_node))
            continue;
        struct media_gpu_route chosen = routes[i];
        memmove(&routes[1], &routes[0], (size_t)i * sizeof(*routes));
        routes[0] = chosen;
        return;
    }
}

int media_gpu_route_decoder_frames(const struct media_gpu_video *video, enum media_gpu_frames frames,
                                   struct media_gpu_decoder *decoder)
{
    if (!video || !decoder)
        return -1;
    memset(decoder, 0, sizeof(*decoder));
    /* Copying every picture back is the person's choice, or the machine's
     * measured record: it costs more than software decoding on some GPUs. */
    if (frames != MEDIA_GPU_FRAMES_IMPORT && !media_gpu_route_copy_back())
        return 0;
    if (video->codec == MEDIA_GPU_CODEC_UNKNOWN || video->bits <= 0
        || video->width <= 0 || video->height <= 0)
        return -1;
    if (video->rgb || video->components != 3 || video->bits < 8 || video->bits > 12)
        return 0;
    struct media_gpu_route *routes = NULL;
    int count = media_gpu_routes(&routes);
    if (frames == MEDIA_GPU_FRAMES_COPY)
        media_gpu_route_prefer_graphics_page(routes, count);
    int unknown = 0;
    for (int i = 0; i < count; i++) {
        struct media_gpu_decoder candidate = { .gpu = routes[i] };
        int supported;
        if (routes[i].vendor_id == 0x10de) {
            candidate.backend = MEDIA_GPU_CUDA;
            supported = media_gpu_cuda_supports(video, &routes[i], candidate.device);
        } else {
            candidate.backend = MEDIA_GPU_VAAPI;
            snprintf(candidate.device, sizeof(candidate.device), "%s", routes[i].render_node);
            supported = media_gpu_vaapi_supports(video, &routes[i]);
        }
        if (supported > 0) {
            *decoder = candidate;
            free(routes);
            return 1;
        }
        unknown |= supported < 0;
    }
    free(routes);
    return unknown || !count ? -1 : 0;
}

int media_gpu_route_decoder(const struct media_gpu_video *video, struct media_gpu_decoder *decoder)
{
    return media_gpu_route_decoder_frames(video, MEDIA_GPU_FRAMES_COPY, decoder);
}
