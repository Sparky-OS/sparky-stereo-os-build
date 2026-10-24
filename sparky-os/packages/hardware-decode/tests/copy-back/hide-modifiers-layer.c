/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
/* Test fixture: a Vulkan layer that hides VK_EXT_image_drm_format_modifier,
 * so a GPU that offers it behaves like RADV on GFX6 to GFX8 (Carrizo, Stoney,
 * Polaris, Hainan), where Mesa offers dma-buf memory without modifiers and
 * libplacebo cannot import decoded surfaces. SPARKY_TEST_HIDE_EXTENSIONS adds
 * more names, separated by spaces: VK_KHR_video_decode_queue as well makes a
 * GPU with Vulkan Video decode behave like the A10's UVD, which RADV does not
 * decode with. Nothing else changes. */
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vk_layer.h>
#include <vulkan/vulkan.h>

#define HIDDEN VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME
#define LAYER_NAME "VK_LAYER_SPARKY_test_hide_drm_format_modifier"
#define EXPORT __attribute__((visibility("default")))

struct entry {
    void *key;
    PFN_vkGetInstanceProcAddr gipa;
    PFN_vkGetDeviceProcAddr gdpa;
    VkInstance instance;
};
static struct entry entries[64];
static int num_entries;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static int hidden(const char *name)
{
    if (!strcmp(name, HIDDEN))
        return 1;
    const char *more = getenv("SPARKY_TEST_HIDE_EXTENSIONS");
    size_t length = strlen(name);
    for (const char *at = more; at && (at = strstr(at, name)); at += length)
        if ((at == more || at[-1] == ' ') && (at[length] == ' ' || !at[length]))
            return 1;
    return 0;
}

static void *key_of(const void *handle)
{
    return *(void **)handle;
}

static struct entry *find(const void *handle)
{
    void *key = key_of(handle);
    struct entry *found = NULL;
    pthread_mutex_lock(&lock);
    for (int i = 0; i < num_entries; i++)
        if (entries[i].key == key)
            found = &entries[i];
    pthread_mutex_unlock(&lock);
    return found;
}

static void add(struct entry e)
{
    pthread_mutex_lock(&lock);
    if (num_entries < 64)
        entries[num_entries++] = e;
    pthread_mutex_unlock(&lock);
}

static VKAPI_ATTR VkResult VKAPI_CALL CreateInstance(const VkInstanceCreateInfo *info,
                                                     const VkAllocationCallbacks *allocator, VkInstance *instance)
{
    VkLayerInstanceCreateInfo *chain = (VkLayerInstanceCreateInfo *)info->pNext;
    while (chain && !(chain->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO && chain->function == VK_LAYER_LINK_INFO))
        chain = (VkLayerInstanceCreateInfo *)chain->pNext;
    if (!chain)
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkGetInstanceProcAddr gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;
    PFN_vkCreateInstance create = (PFN_vkCreateInstance)gipa(VK_NULL_HANDLE, "vkCreateInstance");
    VkResult result = create(info, allocator, instance);
    if (result == VK_SUCCESS)
        add((struct entry){ .key = key_of(*instance), .gipa = gipa, .instance = *instance });
    return result;
}

static VKAPI_ATTR VkResult VKAPI_CALL EnumerateDeviceExtensionProperties(VkPhysicalDevice device, const char *layer,
                                                                         uint32_t *count, VkExtensionProperties *out)
{
    if (layer && !strcmp(layer, LAYER_NAME)) {
        *count = 0;
        return VK_SUCCESS;
    }
    struct entry *e = find(device);
    PFN_vkEnumerateDeviceExtensionProperties next = (PFN_vkEnumerateDeviceExtensionProperties)
        e->gipa(e->instance, "vkEnumerateDeviceExtensionProperties");
    uint32_t total = 0;
    VkResult result = next(device, layer, &total, NULL);
    if (result != VK_SUCCESS)
        return result;
    VkExtensionProperties *all = calloc(total ? total : 1, sizeof(*all));
    if (!all)
        return VK_ERROR_OUT_OF_HOST_MEMORY;
    result = next(device, layer, &total, all);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < total; i++)
        if (!hidden(all[i].extensionName))
            all[kept++] = all[i];
    if (!out) {
        *count = kept;
    } else {
        uint32_t n = *count < kept ? *count : kept;
        memcpy(out, all, n * sizeof(*out));
        if (n < kept)
            result = VK_INCOMPLETE;
        *count = n;
    }
    free(all);
    return result;
}

static VKAPI_ATTR VkResult VKAPI_CALL CreateDevice(VkPhysicalDevice physical, const VkDeviceCreateInfo *info,
                                                   const VkAllocationCallbacks *allocator, VkDevice *device)
{
    VkLayerDeviceCreateInfo *chain = (VkLayerDeviceCreateInfo *)info->pNext;
    while (chain && !(chain->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO && chain->function == VK_LAYER_LINK_INFO))
        chain = (VkLayerDeviceCreateInfo *)chain->pNext;
    if (!chain)
        return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkGetInstanceProcAddr gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkGetDeviceProcAddr gdpa = chain->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;
    struct entry *e = find(physical);
    PFN_vkCreateDevice create = (PFN_vkCreateDevice)gipa(e->instance, "vkCreateDevice");
    VkResult result = create(physical, info, allocator, device);
    if (result == VK_SUCCESS)
        add((struct entry){ .key = key_of(*device), .gdpa = gdpa });
    return result;
}

EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device, const char *name);

EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device, const char *name)
{
    if (!strcmp(name, "vkGetDeviceProcAddr"))
        return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    if (!strcmp(name, "vkGetImageDrmFormatModifierPropertiesEXT"))
        return NULL;
    struct entry *e = find(device);
    return e ? e->gdpa(device, name) : NULL;
}

EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char *name);

EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char *name)
{
    if (!strcmp(name, "vkGetInstanceProcAddr"))
        return (PFN_vkVoidFunction)vkGetInstanceProcAddr;
    if (!strcmp(name, "vkCreateInstance"))
        return (PFN_vkVoidFunction)CreateInstance;
    if (!strcmp(name, "vkEnumerateDeviceExtensionProperties"))
        return (PFN_vkVoidFunction)EnumerateDeviceExtensionProperties;
    if (!strcmp(name, "vkCreateDevice"))
        return (PFN_vkVoidFunction)CreateDevice;
    if (!strcmp(name, "vkGetDeviceProcAddr"))
        return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    if (!instance)
        return NULL;
    struct entry *e = find(instance);
    return e ? e->gipa(instance, name) : NULL;
}
