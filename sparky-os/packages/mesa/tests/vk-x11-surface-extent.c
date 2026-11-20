/* vk-x11-surface-extent: a Vulkan X11 surface's extents must be its window's size.
 *
 * "With Xcb, minImageExtent, maxImageExtent, and currentExtent must always equal the window size" (Vulkan,
 * VK_KHR_xcb_surface; the same for Xlib). The program makes a 640x480 window, creates an xcb and an Xlib surface
 * for it with an allocator that fills every allocation with 0xff (so a field the driver forgets to set reads as
 * true instead of whatever the heap held), asks every physical device for the surface's capabilities and prints
 * PASS or FAIL per device and surface kind; the exit status is 1 when one fails. Written for ORDER 39 of Sparky
 * Stereo OS (Mesa's X11 surface kept three fields of patch 0041 unset). Build:
 *   cc -O2 -o vk-x11-surface-extent vk-x11-surface-extent.c -lvulkan -lX11 -lX11-xcb -lxcb
 */
#define VK_USE_PLATFORM_XCB_KHR
#define VK_USE_PLATFORM_XLIB_KHR
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <X11/Xlib.h>
#include <X11/Xlib-xcb.h>
#include <vulkan/vulkan.h>

static void *VKAPI_PTR dirty_alloc(void *user, size_t size, size_t align, VkSystemAllocationScope scope)
{
	(void)user; (void)scope;
	if (align < sizeof(void *)) align = sizeof(void *);
	void *p = NULL;
	if (posix_memalign(&p, align, size ? size : 1)) return NULL;
	memset(p, 0xff, size);
	return p;
}
static void *VKAPI_PTR dirty_realloc(void *user, void *old, size_t size, size_t align, VkSystemAllocationScope scope)
{
	(void)user; (void)align; (void)scope;
	return realloc(old, size);
}
static void VKAPI_PTR dirty_free(void *user, void *p) { (void)user; free(p); }

int main(void)
{
	const int W = 640, H = 480;
	Display *dpy = XOpenDisplay(NULL);
	if (!dpy) { fprintf(stderr, "no X display\n"); return 2; }
	Window win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, W, H, 0, 0, 0);
	XMapWindow(dpy, win);
	XSync(dpy, False);
	const char *exts[] = {VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_XCB_SURFACE_EXTENSION_NAME, VK_KHR_XLIB_SURFACE_EXTENSION_NAME};
	VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1};
	VkInstanceCreateInfo ici = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app,
	                            .enabledExtensionCount = 3, .ppEnabledExtensionNames = exts};
	VkInstance inst;
	if (vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) { fprintf(stderr, "no Vulkan instance\n"); return 2; }
	const VkAllocationCallbacks dirty = {.pfnAllocation = dirty_alloc, .pfnReallocation = dirty_realloc, .pfnFree = dirty_free};
	VkSurfaceKHR surfaces[2];
	VkXcbSurfaceCreateInfoKHR xcb = {.sType = VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
	                                 .connection = XGetXCBConnection(dpy), .window = (xcb_window_t)win};
	VkXlibSurfaceCreateInfoKHR xlib = {.sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR, .dpy = dpy, .window = win};
	if (vkCreateXcbSurfaceKHR(inst, &xcb, &dirty, &surfaces[0]) != VK_SUCCESS ||
	    vkCreateXlibSurfaceKHR(inst, &xlib, &dirty, &surfaces[1]) != VK_SUCCESS) { fprintf(stderr, "no surface\n"); return 2; }
	uint32_t n = 0;
	vkEnumeratePhysicalDevices(inst, &n, NULL);
	VkPhysicalDevice devs[16];
	if (n > 16) n = 16;
	vkEnumeratePhysicalDevices(inst, &n, devs);
	int fails = 0, checked = 0;
	for (uint32_t i = 0; i < n; i++) {
		VkPhysicalDeviceProperties props;
		vkGetPhysicalDeviceProperties(devs[i], &props);
		for (int s = 0; s < 2; s++) {
			VkSurfaceCapabilitiesKHR caps;
			VkResult r = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(devs[i], surfaces[s], &caps);
			if (r != VK_SUCCESS) { printf("SKIP %s %s: capabilities %d\n", props.deviceName, s ? "xlib" : "xcb", r); continue; }
			const int ok = caps.currentExtent.width == (uint32_t)W && caps.currentExtent.height == (uint32_t)H &&
			               caps.minImageExtent.width == (uint32_t)W && caps.maxImageExtent.width == (uint32_t)W;
			printf("%s %s %s: window %dx%d current %ux%u min %ux%u max %ux%u layers %u\n", ok ? "PASS" : "FAIL",
			       props.deviceName, s ? "xlib" : "xcb", W, H, caps.currentExtent.width, caps.currentExtent.height,
			       caps.minImageExtent.width, caps.minImageExtent.height, caps.maxImageExtent.width,
			       caps.maxImageExtent.height, caps.maxImageArrayLayers);
			fails += !ok; checked++;
		}
	}
	vkDestroySurfaceKHR(inst, surfaces[0], &dirty);
	vkDestroySurfaceKHR(inst, surfaces[1], &dirty);
	vkDestroyInstance(inst, NULL);
	XCloseDisplay(dpy);
	if (!checked) { fprintf(stderr, "no device could be asked\n"); return 2; }
	return fails ? 1 : 0;
}
