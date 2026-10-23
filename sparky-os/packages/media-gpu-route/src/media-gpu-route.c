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

int media_gpu_routes(struct media_gpu_route **out)
{
    *out = NULL;
    uint32_t count = 0;
    if (vkEnumerateInstanceExtensionProperties(NULL, &count, NULL) != VK_SUCCESS)
        return 0;
    VkExtensionProperties *extensions = calloc(count, sizeof(*extensions));
    if (!extensions)
        return 0;
    if (vkEnumerateInstanceExtensionProperties(NULL, &count, extensions) != VK_SUCCESS) {
        free(extensions);
        return 0;
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
        return 0;
    VkPhysicalDevice *devices = NULL;
    struct media_gpu_route *routes = NULL;
    int found = 0;
    if (vkEnumeratePhysicalDevices(instance, &count, NULL) != VK_SUCCESS || !count)
        goto done;
    devices = calloc(count, sizeof(*devices));
    routes = calloc(count, sizeof(*routes));
    if (!devices || !routes || vkEnumeratePhysicalDevices(instance, &count, devices) != VK_SUCCESS)
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
    vkDestroyInstance(instance, NULL);
    if (!found) {
        free(routes);
        return 0;
    }
    *out = routes;
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

int media_gpu_route_decoder(const struct media_gpu_video *video, struct media_gpu_decoder *decoder)
{
    if (!video || !decoder)
        return -1;
    memset(decoder, 0, sizeof(*decoder));
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
