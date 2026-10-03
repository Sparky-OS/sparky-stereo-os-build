# VM run: KWin draws only on the iGPU (AMD, PCI 0b:00.0), so the RTX 3060 stays free to be
# handed to the Sparky Stereo OS development VM. Copy to ~/.config/plasma-workspace/env/,
# log in again; delete it and log in again to give the 3060 back to KWin.
# Colons in the paths are escaped for KWin.
export KWIN_DRM_DEVICES='/dev/dri/by-path/pci-0000\:0b\:00.0-card'
export KWIN_RENDER_NODES='/dev/dri/by-path/pci-0000\:0b\:00.0-render'
# The vendor dispatch would still load NVIDIA's EGL, GLX and Vulkan drivers into KWin and every
# program, and they open the card: Mesa only for this run.
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export __GLX_VENDOR_LIBRARY_NAME=mesa
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json
