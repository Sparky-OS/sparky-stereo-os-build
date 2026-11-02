#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* WINE_UNIX_LIB makes WINAPI the native Unix calling convention. */
typedef int (*set_prop)(void *, const uint16_t *, void *);
int NtUserSetProp(void *window, const uint16_t *name, void *value)
{
    const char prefix[] = "__wine_vulkan_stereo_v1_";
    const char *mode = getenv("WINE254_FAIL_ACK");
    size_t n;
    if ((uintptr_t)name > 65535 && (uintptr_t)value == 0x18003 && mode)
    {
        for (n = 0; n < sizeof(prefix)-1 && name[n] == (uint16_t)prefix[n]; ++n) {}
        if (n == sizeof(prefix)-1 && !strcmp(mode, "fail"))
        {
            fprintf(stderr, "WINE254_INJECT NtUserSetProp hwnd=%p value=0x18003 result=0\n", window);
            return 0;
        }
    }
    void *module = dlopen("/usr/lib/x86_64-linux-gnu/wine/x86_64-unix/win32u.so", RTLD_NOW | RTLD_NOLOAD);
    set_prop real = module ? (set_prop)dlsym(module, "NtUserSetProp") : NULL;
    if (!real || real == NtUserSetProp) { fprintf(stderr, "WINE254_INJECT resolution failed\n"); abort(); }
    int result = real(window, name, value);
    if ((uintptr_t)value == 0x18003) fprintf(stderr, "WINE254_INJECT NtUserSetProp hwnd=%p value=0x18003 result=%d\n",window,result);
    dlclose(module);
    return result;
}

static int fail_declaration(void *display, unsigned long parent, unsigned long child,
                            int layout, int content_class, unsigned subclass,
                            unsigned width, unsigned height)
{
    fprintf(stderr, "WINE254_INJECT stereo_declare_x11_child parent=%lu child=%lu result=-95\n",parent,child);
    return -95;
}

void *dlsym(void *module, const char *name)
{
    typedef void *(*resolver)(void *, const char *);
    resolver real = (resolver)dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    const char *mode = getenv("WINE254_FAIL_ACK");
    if (!real) abort();
    if (mode && !strcmp(mode,"fail-declare") && !strcmp(name,"stereo_declare_x11_child"))
        return (void *)fail_declaration;
    return real(module,name);
}
