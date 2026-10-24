/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
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
