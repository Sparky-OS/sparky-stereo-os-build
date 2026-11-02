/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
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
 * that copies its pictures back decodes there, and on another GPU only where the person allows it
 * (media_gpu_route_other_gpu). A caller that imports decoded surfaces keeps the graphics stack's order,
 * because its renderer draws on the GPU the program was started on, and the page's launch environment puts it
 * there. Nothing is written. A GPU chosen at launch (DRI_PRIME, a Vulkan device selection, an NVIDIA offload)
 * is more specific than the page and wins, and a computer without the page has nothing to ask. A page that
 * fails, answers nothing or names a GPU this program cannot open is said, and no other GPU is put in its place
 * (Daniel, 2026-11-01: "either it works or not and the user must know"). The page is asked at each choice, so a
 * new choice on the page reaches a running program's next video. */
static int page_installed(void)
{
    const char *path = getenv("PATH");
    if (!path || !*path)
        path = "/usr/local/bin:/usr/bin:/bin";
    while (*path) {
        size_t length = strcspn(path, ":");
        char candidate[1024];
        if (length && snprintf(candidate, sizeof(candidate), "%.*s/sparky-stereo-gpu-env", (int)length, path) < (int)sizeof(candidate)
            && !access(candidate, X_OK))
            return 1;
        path += length + (path[length] == ':');
    }
    return 0;
}

enum media_gpu_page media_gpu_route_prefer_graphics_page(struct media_gpu_route *routes, int count, char node[128], int *status)
{
    static const char *const launch_choice[] = { "DRI_PRIME", "MESA_VK_DEVICE_SELECT", "VK_LOADER_DRIVERS_SELECT", "__NV_PRIME_RENDER_OFFLOAD" };
    node[0] = '\0';
    *status = 0;
    for (size_t i = 0; i < sizeof(launch_choice) / sizeof(launch_choice[0]); i++)
        if (getenv(launch_choice[i]))
            return MEDIA_GPU_PAGE_NOT_ASKED;
    if (!page_installed())
        return MEDIA_GPU_PAGE_NOT_ASKED;
    /* its stderr is the program's: the page says itself why a choice cannot be used, in the person's language */
    FILE *answer = popen("sparky-stereo-gpu-env --category players --print render-node", "re");
    if (!answer) {
        *status = -1;
        return MEDIA_GPU_PAGE_FAILED;
    }
    if (!fgets(node, 128, answer))
        node[0] = '\0';
    int closed = pclose(answer);
    node[strcspn(node, "\n")] = '\0';
    if (closed != 0 || !node[0]) {
        *status = closed == -1 ? -1 : WIFEXITED(closed) ? WEXITSTATUS(closed) : 128 + WTERMSIG(closed);
        return MEDIA_GPU_PAGE_FAILED;
    }
    for (int i = 0; i < count; i++) {
        if (strcmp(routes[i].render_node, node))
            continue;
        struct media_gpu_route chosen = routes[i];
        memmove(&routes[1], &routes[0], (size_t)i * sizeof(*routes));
        routes[0] = chosen;
        return MEDIA_GPU_PAGE_NAMED;
    }
    return MEDIA_GPU_PAGE_NOT_FOUND;
}

static void say(char *text, size_t size, const char *message)
{
    if (text && size)
        snprintf(text, size, "%s", message);
}

static int supports(const struct media_gpu_video *video, const struct media_gpu_route *route, struct media_gpu_decoder *candidate)
{
    candidate->gpu = *route;
    if (route->vendor_id == 0x10de) {
        candidate->backend = MEDIA_GPU_CUDA;
        return media_gpu_cuda_supports(video, route, candidate->device);
    }
    candidate->backend = MEDIA_GPU_VAAPI;
    snprintf(candidate->device, sizeof(candidate->device), "%s", route->render_node);
    return media_gpu_vaapi_supports(video, route);
}

int media_gpu_route_decoder_said(const struct media_gpu_video *video, enum media_gpu_frames frames,
                                 struct media_gpu_decoder *decoder, char *text, size_t size)
{
    say(text, size, "");
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
    char message[1024];
    enum media_gpu_page page = MEDIA_GPU_PAGE_NOT_ASKED;
    if (frames == MEDIA_GPU_FRAMES_COPY) {
        char node[128];
        int status;
        page = media_gpu_route_prefer_graphics_page(routes, count, node, &status);
        if (page == MEDIA_GPU_PAGE_FAILED || page == MEDIA_GPU_PAGE_NOT_FOUND) {
            if (page == MEDIA_GPU_PAGE_FAILED)
                snprintf(message, sizeof(message), media_gpu_route_text(MEDIA_GPU_TEXT_PAGE_FAILED), status);
            else
                snprintf(message, sizeof(message), media_gpu_route_text(MEDIA_GPU_TEXT_NOT_FOUND), node);
            say(text, size, message);
            free(routes);
            return -2;
        }
    }
    int unknown = 0;
    for (int i = 0; i < count; i++) {
        struct media_gpu_decoder candidate;
        memset(&candidate, 0, sizeof(candidate));
        int supported = supports(video, &routes[i], &candidate);
        if (supported > 0) {
            *decoder = candidate;
            if (page == MEDIA_GPU_PAGE_NAMED && i > 0) {
                snprintf(message, sizeof(message), media_gpu_route_text(MEDIA_GPU_TEXT_OTHER_GPU), routes[i].name);
                say(text, size, message);
            }
            free(routes);
            return 1;
        }
        unknown |= supported < 0;
        /* the players' GPU cannot decode it: another GPU only where the person allows it */
        if (page == MEDIA_GPU_PAGE_NAMED && i == 0 && !media_gpu_route_other_gpu()) {
            snprintf(message, sizeof(message), media_gpu_route_text(supported == 0 ? MEDIA_GPU_TEXT_CANNOT_DECODE : MEDIA_GPU_TEXT_UNKNOWN),
                     routes[0].name);
            say(text, size, message);
            free(routes);
            /* a driver that does not answer is never taken for "decodes it", nor for another GPU's turn */
            return supported == 0 ? 0 : -2;
        }
    }
    free(routes);
    return unknown || !count ? -1 : 0;
}

int media_gpu_route_decoder_frames(const struct media_gpu_video *video, enum media_gpu_frames frames,
                                   struct media_gpu_decoder *decoder)
{
    /* the 0.2 callers (MLT, VLC) take another GPU on -1: when the GPU chosen for players cannot be resolved they
     * get software, and the reason goes where the program keeps its messages */
    char text[1024];
    int result = media_gpu_route_decoder_said(video, frames, decoder, text, sizeof(text));
    if (text[0])
        fprintf(stderr, "media-gpu-route: %s\n", text);
    return result == -2 ? 0 : result;
}

int media_gpu_route_decoder(const struct media_gpu_video *video, struct media_gpu_decoder *decoder)
{
    return media_gpu_route_decoder_frames(video, MEDIA_GPU_FRAMES_COPY, decoder);
}
