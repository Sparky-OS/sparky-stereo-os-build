/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: LGPL-2.1-or-later */
#include <libplacebo/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <vulkan/vulkan.h>
static void show(const char *label, VkPhysicalDevice device)
{
    VkPhysicalDeviceDrmPropertiesEXT drm = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT };
    VkPhysicalDeviceProperties2 props = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &drm };
    vkGetPhysicalDeviceProperties2(device, &props);
    printf("%s vendor=%04x name=%s render=%lld:%lld\n", label, props.properties.vendorID,
           props.properties.deviceName, (long long) drm.renderMajor, (long long) drm.renderMinor);
}
int main(void)
{
    const char *extensions[] = { "VK_KHR_surface", "VK_KHR_wayland_surface" };
    pl_vk_inst instance = pl_vk_inst_create(NULL, pl_vk_inst_params(.extensions = extensions, .num_extensions = 2));
    if (!instance) return 2;
    uint32_t count = 0;
    if (vkEnumeratePhysicalDevices(instance->instance, &count, NULL) != VK_SUCCESS || !count) return 3;
    VkPhysicalDevice *devices = calloc(count, sizeof(*devices));
    if (vkEnumeratePhysicalDevices(instance->instance, &count, devices) != VK_SUCCESS) return 4;
    VkPhysicalDevice first = VK_NULL_HANDLE, last_hardware = VK_NULL_HANDLE;
    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devices[i], &p);
        if (p.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU) {
            if (!first) first = devices[i];
            last_hardware = devices[i];
        }
        show("ENUM", devices[i]);
    }
    VkPhysicalDevice choice = pl_vulkan_choose_device(NULL, pl_vulkan_device_params(.instance = instance->instance));
    if (!first || !choice) return 5;
    show("FIRST_HARDWARE", first);
    show("DEFAULT", choice);
    int result = choice != first;
    // Explicit user choice is still an override.
    VkPhysicalDeviceProperties requested;
    vkGetPhysicalDeviceProperties(last_hardware, &requested);
    VkPhysicalDevice explicit = pl_vulkan_choose_device(NULL, pl_vulkan_device_params(.instance = instance->instance, .device_name = requested.deviceName));
    if (explicit != last_hardware) result = 6;
    show("EXPLICIT_NAME", explicit);
    VkPhysicalDeviceIDProperties id = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES };
    VkPhysicalDeviceProperties2 props = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &id };
    vkGetPhysicalDeviceProperties2(last_hardware, &props);
    struct pl_vulkan_device_params params = { .instance = instance->instance };
    for (unsigned i = 0; i < VK_UUID_SIZE; i++) params.device_uuid[i] = id.deviceUUID[i];
    explicit = pl_vulkan_choose_device(NULL, &params);
    if (explicit != last_hardware) result = 7;
    show("EXPLICIT_UUID", explicit);
    free(devices);
    pl_vk_inst_destroy(&instance);
    return result;
}
