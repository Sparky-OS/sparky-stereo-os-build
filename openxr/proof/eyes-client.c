// Test aid: an OpenXR client (XR_KHR_vulkan_enable2) that clears the left eye red and the
// right eye blue every frame, so a capture of a spectator or display window can be read by
// a script. No shaders, no window of its own. usage: eyes-client [frames]
#define XR_USE_GRAPHICS_API_VULKAN
#include <vulkan/vulkan.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define CHECK(x)                                                                                                       \
	do {                                                                                                           \
		XrResult r_ = (x);                                                                                     \
		if (XR_FAILED(r_)) {                                                                                   \
			fprintf(stderr, "%s failed: %d\n", #x, r_);                                                    \
			exit(1);                                                                                       \
		}                                                                                                      \
	} while (0)
#define VK_CHECK(x)                                                                                                    \
	do {                                                                                                           \
		VkResult r_ = (x);                                                                                     \
		if (r_ != VK_SUCCESS) {                                                                                \
			fprintf(stderr, "%s failed: %d\n", #x, r_);                                                    \
			exit(1);                                                                                       \
		}                                                                                                      \
	} while (0)

struct eye
{
	XrSwapchain swapchain;
	uint32_t width, height, count;
	XrSwapchainImageVulkanKHR *images;
};

int
main(int argc, char **argv)
{
	int frames = argc > 1 ? atoi(argv[1]) : 300;

	const char *ext = XR_KHR_VULKAN_ENABLE2_EXTENSION_NAME;
	XrInstanceCreateInfo ici = {XR_TYPE_INSTANCE_CREATE_INFO};
	strcpy(ici.applicationInfo.applicationName, "eyes-client");
	ici.applicationInfo.applicationVersion = 1;
	strcpy(ici.applicationInfo.engineName, "none");
	ici.applicationInfo.apiVersion = XR_API_VERSION_1_0;
	ici.enabledExtensionCount = 1;
	ici.enabledExtensionNames = &ext;
	XrInstance instance;
	CHECK(xrCreateInstance(&ici, &instance));

	XrSystemGetInfo sgi = {XR_TYPE_SYSTEM_GET_INFO, NULL, XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY};
	XrSystemId system;
	CHECK(xrGetSystem(instance, &sgi, &system));

	PFN_xrGetVulkanGraphicsRequirements2KHR getReq;
	PFN_xrCreateVulkanInstanceKHR createVkInstance;
	PFN_xrGetVulkanGraphicsDevice2KHR getVkDevice;
	PFN_xrCreateVulkanDeviceKHR createVkDevice;
	CHECK(xrGetInstanceProcAddr(instance, "xrGetVulkanGraphicsRequirements2KHR", (PFN_xrVoidFunction *)&getReq));
	CHECK(xrGetInstanceProcAddr(instance, "xrCreateVulkanInstanceKHR", (PFN_xrVoidFunction *)&createVkInstance));
	CHECK(xrGetInstanceProcAddr(instance, "xrGetVulkanGraphicsDevice2KHR", (PFN_xrVoidFunction *)&getVkDevice));
	CHECK(xrGetInstanceProcAddr(instance, "xrCreateVulkanDeviceKHR", (PFN_xrVoidFunction *)&createVkDevice));

	XrGraphicsRequirementsVulkan2KHR req = {XR_TYPE_GRAPHICS_REQUIREMENTS_VULKAN2_KHR};
	CHECK(getReq(instance, system, &req));

	VkApplicationInfo vai = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
	vai.pApplicationName = "eyes-client";
	vai.apiVersion = VK_API_VERSION_1_1;
	VkInstanceCreateInfo vici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
	vici.pApplicationInfo = &vai;
	XrVulkanInstanceCreateInfoKHR xvici = {XR_TYPE_VULKAN_INSTANCE_CREATE_INFO_KHR};
	xvici.systemId = system;
	xvici.pfnGetInstanceProcAddr = vkGetInstanceProcAddr;
	xvici.vulkanCreateInfo = &vici;
	VkInstance vk;
	VkResult vr;
	CHECK(createVkInstance(instance, &xvici, &vk, &vr));
	VK_CHECK(vr);

	XrVulkanGraphicsDeviceGetInfoKHR gdgi = {XR_TYPE_VULKAN_GRAPHICS_DEVICE_GET_INFO_KHR};
	gdgi.systemId = system;
	gdgi.vulkanInstance = vk;
	VkPhysicalDevice pdev;
	CHECK(getVkDevice(instance, &gdgi, &pdev));

	uint32_t qf_count = 0;
	vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qf_count, NULL);
	VkQueueFamilyProperties *qfs = calloc(qf_count, sizeof(*qfs));
	vkGetPhysicalDeviceQueueFamilyProperties(pdev, &qf_count, qfs);
	uint32_t qf = 0;
	for (uint32_t i = 0; i < qf_count; i++) {
		if (qfs[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
			qf = i;
			break;
		}
	}
	float prio = 1.0f;
	VkDeviceQueueCreateInfo qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
	qci.queueFamilyIndex = qf;
	qci.queueCount = 1;
	qci.pQueuePriorities = &prio;
	VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
	dci.queueCreateInfoCount = 1;
	dci.pQueueCreateInfos = &qci;
	XrVulkanDeviceCreateInfoKHR xdci = {XR_TYPE_VULKAN_DEVICE_CREATE_INFO_KHR};
	xdci.systemId = system;
	xdci.pfnGetInstanceProcAddr = vkGetInstanceProcAddr;
	xdci.vulkanPhysicalDevice = pdev;
	xdci.vulkanCreateInfo = &dci;
	VkDevice dev;
	CHECK(createVkDevice(instance, &xdci, &dev, &vr));
	VK_CHECK(vr);
	VkQueue queue;
	vkGetDeviceQueue(dev, qf, 0, &queue);

	VkCommandPoolCreateInfo cpci = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
	cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	cpci.queueFamilyIndex = qf;
	VkCommandPool pool;
	VK_CHECK(vkCreateCommandPool(dev, &cpci, NULL, &pool));
	VkCommandBufferAllocateInfo cbai = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
	cbai.commandPool = pool;
	cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	cbai.commandBufferCount = 1;
	VkCommandBuffer cmd;
	VK_CHECK(vkAllocateCommandBuffers(dev, &cbai, &cmd));

	XrGraphicsBindingVulkan2KHR binding = {XR_TYPE_GRAPHICS_BINDING_VULKAN2_KHR};
	binding.instance = vk;
	binding.physicalDevice = pdev;
	binding.device = dev;
	binding.queueFamilyIndex = qf;
	binding.queueIndex = 0;
	XrSessionCreateInfo sci = {XR_TYPE_SESSION_CREATE_INFO};
	sci.next = &binding;
	sci.systemId = system;
	XrSession session;
	CHECK(xrCreateSession(instance, &sci, &session));

	uint32_t view_count = 0;
	CHECK(xrEnumerateViewConfigurationViews(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0,
	                                        &view_count, NULL));
	if (view_count != 2) {
		fprintf(stderr, "expected 2 views, got %u\n", view_count);
		return 1;
	}
	XrViewConfigurationView vcv[2] = {{XR_TYPE_VIEW_CONFIGURATION_VIEW}, {XR_TYPE_VIEW_CONFIGURATION_VIEW}};
	CHECK(xrEnumerateViewConfigurationViews(instance, system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 2,
	                                        &view_count, vcv));

	uint32_t fmt_count = 0;
	CHECK(xrEnumerateSwapchainFormats(session, 0, &fmt_count, NULL));
	int64_t *fmts = calloc(fmt_count, sizeof(int64_t));
	CHECK(xrEnumerateSwapchainFormats(session, fmt_count, &fmt_count, fmts));
	int64_t fmt = fmts[0];
	for (uint32_t i = 0; i < fmt_count; i++) {
		if (fmts[i] == VK_FORMAT_R8G8B8A8_SRGB || fmts[i] == VK_FORMAT_B8G8R8A8_SRGB) {
			fmt = fmts[i];
			break;
		}
	}

	struct eye eyes[2];
	for (int i = 0; i < 2; i++) {
		XrSwapchainCreateInfo swci = {XR_TYPE_SWAPCHAIN_CREATE_INFO};
		swci.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT | XR_SWAPCHAIN_USAGE_TRANSFER_DST_BIT;
		swci.format = fmt;
		swci.sampleCount = 1;
		swci.width = vcv[i].recommendedImageRectWidth;
		swci.height = vcv[i].recommendedImageRectHeight;
		swci.faceCount = 1;
		swci.arraySize = 1;
		swci.mipCount = 1;
		CHECK(xrCreateSwapchain(session, &swci, &eyes[i].swapchain));
		eyes[i].width = swci.width;
		eyes[i].height = swci.height;
		CHECK(xrEnumerateSwapchainImages(eyes[i].swapchain, 0, &eyes[i].count, NULL));
		eyes[i].images = calloc(eyes[i].count, sizeof(XrSwapchainImageVulkanKHR));
		for (uint32_t j = 0; j < eyes[i].count; j++) {
			eyes[i].images[j].type = XR_TYPE_SWAPCHAIN_IMAGE_VULKAN_KHR;
		}
		CHECK(xrEnumerateSwapchainImages(eyes[i].swapchain, eyes[i].count, &eyes[i].count,
		                                 (XrSwapchainImageBaseHeader *)eyes[i].images));
		printf("view %d: %ux%u, %u images, format %lld\n", i, eyes[i].width, eyes[i].height, eyes[i].count,
		       (long long)fmt);
	}

	XrReferenceSpaceCreateInfo rsci = {XR_TYPE_REFERENCE_SPACE_CREATE_INFO};
	rsci.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_LOCAL;
	rsci.poseInReferenceSpace.orientation.w = 1.0f;
	XrSpace space;
	CHECK(xrCreateReferenceSpace(session, &rsci, &space));

	VkClearColorValue colours[2] = {{{1.0f, 0.0f, 0.0f, 1.0f}}, {{0.0f, 0.0f, 1.0f, 1.0f}}};
	if (getenv("EYES_SWAP") != NULL) { // mutant for the proof: the check must fail
		VkClearColorValue t = colours[0];
		colours[0] = colours[1];
		colours[1] = t;
	}

	bool running = true, session_running = false, exit_requested = false;
	int rendered = 0;
	while (running) {
		XrEventDataBuffer ev = {XR_TYPE_EVENT_DATA_BUFFER};
		while (xrPollEvent(instance, &ev) == XR_SUCCESS) {
			if (ev.type == XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED) {
				XrEventDataSessionStateChanged *s = (XrEventDataSessionStateChanged *)&ev;
				switch (s->state) {
				case XR_SESSION_STATE_READY: {
					XrSessionBeginInfo bi = {XR_TYPE_SESSION_BEGIN_INFO};
					bi.primaryViewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
					CHECK(xrBeginSession(session, &bi));
					session_running = true;
				} break;
				case XR_SESSION_STATE_STOPPING:
					CHECK(xrEndSession(session));
					session_running = false;
					break;
				case XR_SESSION_STATE_EXITING:
				case XR_SESSION_STATE_LOSS_PENDING: running = false; break;
				default: break;
				}
			} else if (ev.type == XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING) {
				running = false;
			}
			ev.type = XR_TYPE_EVENT_DATA_BUFFER;
			ev.next = NULL;
		}
		if (!session_running) {
			continue;
		}

		XrFrameState fs = {XR_TYPE_FRAME_STATE};
		XrFrameWaitInfo fwi = {XR_TYPE_FRAME_WAIT_INFO};
		CHECK(xrWaitFrame(session, &fwi, &fs));
		XrFrameBeginInfo fbi = {XR_TYPE_FRAME_BEGIN_INFO};
		CHECK(xrBeginFrame(session, &fbi));

		XrCompositionLayerProjectionView pv[2] = {{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},
		                                          {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW}};
		XrCompositionLayerProjection layer = {XR_TYPE_COMPOSITION_LAYER_PROJECTION};
		const XrCompositionLayerBaseHeader *layers[1] = {(XrCompositionLayerBaseHeader *)&layer};
		uint32_t layer_count = 0;

		if (fs.shouldRender) {
			XrView views[2] = {{XR_TYPE_VIEW}, {XR_TYPE_VIEW}};
			XrViewState vs = {XR_TYPE_VIEW_STATE};
			XrViewLocateInfo vli = {XR_TYPE_VIEW_LOCATE_INFO};
			vli.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
			vli.displayTime = fs.predictedDisplayTime;
			vli.space = space;
			uint32_t located = 0;
			CHECK(xrLocateViews(session, &vli, &vs, 2, &located, views));

			for (int i = 0; i < 2; i++) {
				uint32_t idx;
				XrSwapchainImageAcquireInfo ai = {XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
				CHECK(xrAcquireSwapchainImage(eyes[i].swapchain, &ai, &idx));
				XrSwapchainImageWaitInfo wi = {XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
				wi.timeout = XR_INFINITE_DURATION;
				CHECK(xrWaitSwapchainImage(eyes[i].swapchain, &wi));

				VkImage img = eyes[i].images[idx].image;
				VkCommandBufferBeginInfo cbbi = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
				cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
				VK_CHECK(vkBeginCommandBuffer(cmd, &cbbi));
				VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
				VkImageMemoryBarrier to_dst = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
				to_dst.srcAccessMask = 0;
				to_dst.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
				to_dst.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
				to_dst.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
				to_dst.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
				to_dst.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
				to_dst.image = img;
				to_dst.subresourceRange = range;
				vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
				                     0, NULL, 0, NULL, 1, &to_dst);
				vkCmdClearColorImage(cmd, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &colours[i], 1, &range);
				VkImageMemoryBarrier to_attach = to_dst;
				to_attach.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
				to_attach.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
				to_attach.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
				to_attach.newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
				vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
				                     VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, NULL, 0, NULL, 1,
				                     &to_attach);
				VK_CHECK(vkEndCommandBuffer(cmd));
				VkSubmitInfo si = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
				si.commandBufferCount = 1;
				si.pCommandBuffers = &cmd;
				VK_CHECK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
				VK_CHECK(vkQueueWaitIdle(queue));

				XrSwapchainImageReleaseInfo ri = {XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
				CHECK(xrReleaseSwapchainImage(eyes[i].swapchain, &ri));

				pv[i].pose = views[i].pose;
				pv[i].fov = views[i].fov;
				pv[i].subImage.swapchain = eyes[i].swapchain;
				pv[i].subImage.imageRect.offset.x = 0;
				pv[i].subImage.imageRect.offset.y = 0;
				pv[i].subImage.imageRect.extent.width = (int32_t)eyes[i].width;
				pv[i].subImage.imageRect.extent.height = (int32_t)eyes[i].height;
				pv[i].subImage.imageArrayIndex = 0;
			}
			layer.space = space;
			layer.viewCount = 2;
			layer.views = pv;
			layer_count = 1;
			rendered++;
			if (rendered == 1) {
				printf("first frame: left fov %.3f/%.3f right fov %.3f/%.3f, eye x %.4f / %.4f\n",
				       views[0].fov.angleLeft, views[0].fov.angleRight, views[1].fov.angleLeft,
				       views[1].fov.angleRight, views[0].pose.position.x, views[1].pose.position.x);
				fflush(stdout);
			}
		}

		XrFrameEndInfo fei = {XR_TYPE_FRAME_END_INFO};
		fei.displayTime = fs.predictedDisplayTime;
		fei.environmentBlendMode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
		fei.layerCount = layer_count;
		fei.layers = layers;
		CHECK(xrEndFrame(session, &fei));

		if (rendered >= frames && !exit_requested) {
			CHECK(xrRequestExitSession(session));
			exit_requested = true;
		}
	}
	printf("rendered %d frames\n", rendered);

	for (int i = 0; i < 2; i++) {
		xrDestroySwapchain(eyes[i].swapchain);
	}
	xrDestroySpace(space);
	xrDestroySession(session);
	vkDestroyCommandPool(dev, pool, NULL);
	vkDestroyDevice(dev, NULL);
	vkDestroyInstance(vk, NULL);
	xrDestroyInstance(instance);
	return 0;
}
