/* SPDX-License-Identifier: MIT
 * Diagnostic client-side shim: submit a raw packed NAL before the first slice.
 * It never maps or modifies the encoded output. Run one encoder per process.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <va/va.h>

static unsigned packed_type;
static unsigned picture;
static int submitted;
static int raw_enabled;
static struct header_buffer {
    VABufferID id;
    VABufferType type;
    unsigned size;
    struct header_buffer *next;
} *headers;

static void *symbol(const char *name)
{
    void *p = dlsym(RTLD_NEXT, name);
    if (!p) {
        fprintf(stderr, "probe: missing %s\n", name);
        exit(2);
    }
    return p;
}

VAStatus vaCreateBuffer(VADisplay d, VAContextID context, VABufferType type,
                        unsigned size, unsigned count, void *data, VABufferID *id)
{
    VAStatus (*real)(VADisplay, VAContextID, VABufferType, unsigned, unsigned,
                     void *, VABufferID *) = symbol("vaCreateBuffer");
    VAStatus status = real(d, context, type, size, count, data, id);
    if (status == VA_STATUS_SUCCESS &&
        (type == VAEncPackedHeaderParameterBufferType || type == VAEncPackedHeaderDataBufferType)) {
        struct header_buffer *h = malloc(sizeof(*h));
        if (!h) {
            vaDestroyBuffer(d, *id);
            return VA_STATUS_ERROR_ALLOCATION_FAILED;
        }
        *h = (struct header_buffer){*id, type, size * count, headers};
        headers = h;
    }
    return status;
}

VAStatus vaDestroyBuffer(VADisplay d, VABufferID id)
{
    VAStatus (*real)(VADisplay, VABufferID) = symbol("vaDestroyBuffer");
    struct header_buffer **p = &headers;
    while (*p) {
        if ((*p)->id == id) {
            struct header_buffer *old = *p;
            *p = old->next;
            free(old);
            break;
        }
        p = &(*p)->next;
    }
    return real(d, id);
}

VAStatus vaCreateConfig(VADisplay d, VAProfile profile, VAEntrypoint entry,
                        VAConfigAttrib *attrs, int count, VAConfigID *config)
{
    VAStatus (*real)(VADisplay, VAProfile, VAEntrypoint, VAConfigAttrib *, int,
                     VAConfigID *) = symbol("vaCreateConfig");
    raw_enabled = 0;
    for (int i = 0; i < count; i++) {
        if (attrs[i].type == VAConfigAttribEncPackedHeaders) {
            raw_enabled = !!(attrs[i].value & (VA_ENC_PACKED_HEADER_RAW_DATA |
                                               VA_ENC_PACKED_HEADER_MISC));
            fprintf(stderr, "probe: packed_headers=0x%x\n", attrs[i].value);
        }
    }
    return real(d, profile, entry, attrs, count, config);
}

VAStatus vaBeginPicture(VADisplay d, VAContextID context, VASurfaceID surface)
{
    VAStatus (*real)(VADisplay, VAContextID, VASurfaceID) = symbol("vaBeginPicture");
    submitted = 0;
    packed_type = 0;
    picture++;
    return real(d, context, surface);
}

static VAStatus submit_sei(VADisplay d, VAContextID context)
{
    const char *path = getenv("PROBE_SEI");
    if (!raw_enabled) {
        fprintf(stderr, "probe: raw/misc packed headers were not enabled\n");
        return VA_STATUS_ERROR_UNSUPPORTED_BUFFERTYPE;
    }
    unsigned char bytes[4096];
    VABufferID buffers[2];
    VAStatus status;
    VAStatus (*render)(VADisplay, VAContextID, VABufferID *, int) = symbol("vaRenderPicture");
    FILE *input = fopen(path, "rb");
    if (!input) {
        perror("probe: open SEI");
        return VA_STATUS_ERROR_INVALID_PARAMETER;
    }
    size_t size = fread(bytes, 1, sizeof(bytes), input);
    int invalid = ferror(input) || !size || size == sizeof(bytes);
    fclose(input);
    if (invalid)
        return VA_STATUS_ERROR_INVALID_PARAMETER;
    VAEncPackedHeaderParameterBuffer param = {
        .type = VAEncPackedHeaderRawData,
        .bit_length = (unsigned)size * 8,
        .has_emulation_bytes = 1,
    };
    status = vaCreateBuffer(d, context, VAEncPackedHeaderParameterBufferType,
                            sizeof(param), 1, &param, &buffers[0]);
    if (status != VA_STATUS_SUCCESS)
        return status;
    status = vaCreateBuffer(d, context, VAEncPackedHeaderDataBufferType,
                            size, 1, bytes, &buffers[1]);
    if (status != VA_STATUS_SUCCESS) {
        vaDestroyBuffer(d, buffers[0]);
        return status;
    }
    status = render(d, context, buffers, 2);
    fprintf(stderr, "probe: submitted picture=%u status=%d bytes=", picture, status);
    for (size_t i = 0; i < size; i++)
        fprintf(stderr, "%02x", bytes[i]);
    fprintf(stderr, "\n");
    vaDestroyBuffer(d, buffers[1]);
    vaDestroyBuffer(d, buffers[0]);
    return status;
}

VAStatus vaRenderPicture(VADisplay d, VAContextID context, VABufferID *buffers,
                         int count)
{
    VAStatus (*real)(VADisplay, VAContextID, VABufferID *, int) = symbol("vaRenderPicture");
    for (int i = 0; i < count; i++) {
        struct header_buffer *h = headers;
        while (h && h->id != buffers[i])
            h = h->next;
        if (!h)
            continue;
        VABufferType type = h->type;
        unsigned size = h->size;
        VAStatus status;
        if (type == VAEncPackedHeaderParameterBufferType ||
            type == VAEncPackedHeaderDataBufferType) {
            void *data;
            status = vaMapBuffer(d, buffers[i], &data);
            if (status != VA_STATUS_SUCCESS)
                return status;
            if (type == VAEncPackedHeaderParameterBufferType) {
                packed_type = ((VAEncPackedHeaderParameterBuffer *)data)->type;
            } else {
                fprintf(stderr, "probe: client picture=%u type=%u bytes=", picture, packed_type);
                for (unsigned j = 0; j < size; j++)
                    fprintf(stderr, "%02x", ((unsigned char *)data)[j]);
                fprintf(stderr, "\n");
            }
            vaUnmapBuffer(d, buffers[i]);
            if (type == VAEncPackedHeaderParameterBufferType &&
                packed_type == VAEncPackedHeaderSlice && !submitted && getenv("PROBE_SEI")) {
                status = submit_sei(d, context);
                if (status != VA_STATUS_SUCCESS)
                    return status;
                submitted = 1;
            }
        }
    }
    return real(d, context, buffers, count);
}

VAStatus vaEndPicture(VADisplay d, VAContextID context)
{
    VAStatus (*real)(VADisplay, VAContextID) = symbol("vaEndPicture");
    if (getenv("PROBE_SEI") && !submitted) {
        fprintf(stderr, "probe: no packed slice header; no SEI submitted\n");
        return VA_STATUS_ERROR_INVALID_PARAMETER;
    }
    return real(d, context);
}
