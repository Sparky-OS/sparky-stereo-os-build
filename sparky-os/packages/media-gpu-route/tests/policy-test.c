/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
/* The copy-back choice, read from recorded configuration fixtures. */
#include "media-gpu-route.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char root[256];
static int failures;

static void write_file(const char *dir, const char *text)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", root, dir);
    mkdir(path, 0700);
    snprintf(path, sizeof(path), "%s/%s/sparky-stereo-graphicsrc", root, dir);
    FILE *file = fopen(path, "w");
    if (!file) {
        perror(path);
        exit(1);
    }
    fputs(text, file);
    fclose(file);
}

static void dirs(const char *system, const char *user)
{
    char path[1024];
    unsetenv("MEDIA_GPU_ROUTE_COPY_BACK");
    if (system) {
        char list[1024] = "";
        const char *start = system;
        while (*start) {
            const char *end = strchr(start, ':');
            size_t length = end ? (size_t)(end - start) : strlen(start);
            snprintf(path, sizeof(path), "%s%s%s/%.*s", list, *list ? ":" : "", root, (int)length, start);
            snprintf(list, sizeof(list), "%s", path);
            start += length + !!end;
        }
        setenv("XDG_CONFIG_DIRS", list, 1);
    } else {
        snprintf(path, sizeof(path), "%s/no-system", root);
        setenv("XDG_CONFIG_DIRS", path, 1);
    }
    snprintf(path, sizeof(path), "%s/%s", root, user ? user : "no-user");
    setenv("XDG_CONFIG_HOME", path, 1);
}

static void expect(const char *name, int wanted)
{
    int got = media_gpu_route_copy_back();
    printf("%-58s copy-back=%d %s\n", name, got, got == wanted ? "ok" : "FAIL");
    failures += got != wanted;
}

int main(void)
{
    snprintf(root, sizeof(root), "%s/media-gpu-route-policy-XXXXXX", getenv("TMPDIR") ? getenv("TMPDIR") : "/tmp");
    if (!mkdtemp(root)) {
        perror("mkdtemp");
        return 1;
    }
    setenv("HOME", root, 1);
    write_file("machine-yes", "[General]\nMainGpu=pci-0000:00:01.0\n\n[Decoding]\nCopyBack=true\n");
    write_file("machine-no", "[Decoding]\nCopyBack=false\n");
    write_file("person-no", "# The person's own choice\n[Decoding]\nCopyBack=off\n");
    write_file("person-yes", "[Render]\nPlayers=integrated\n[Decoding]\nCopyBack = yes\n");
    write_file("other-group", "[Render]\nCopyBack=true\n");
    write_file("marked", "[Decoding][$i]\nCopyBack[$i]=1\n");
    write_file("commented", "[Decoding]\n# CopyBack=true\nCopyBack[de]=true\n");
    write_file("unreadable-value", "[Decoding]\nCopyBack=perhaps\n");

    dirs(NULL, NULL);
    expect("nothing recorded: never assumed", 0);
    dirs("machine-yes", NULL);
    expect("machine record allows it", 1);
    dirs("machine-no:machine-yes", NULL);
    expect("the first system directory is the most important", 0);
    dirs("machine-yes:machine-no", NULL);
    expect("the first system directory is the most important, again", 1);
    dirs("machine-yes", "person-no");
    expect("the person's choice over the machine record", 0);
    dirs("machine-no", "person-yes");
    expect("the person's choice over the machine record, again", 1);
    dirs(NULL, "other-group");
    expect("only group [Decoding] counts", 0);
    dirs(NULL, "marked");
    expect("KConfig's [$i] marks are read", 1);
    dirs(NULL, "commented");
    expect("comments and localized keys are not the entry", 0);
    dirs("machine-yes", "unreadable-value");
    expect("an unreadable value leaves the machine record", 1);
    dirs(NULL, "person-yes");
    setenv("MEDIA_GPU_ROUTE_COPY_BACK", "false", 1);
    expect("the environment over every file", 0);
    dirs(NULL, NULL);
    setenv("MEDIA_GPU_ROUTE_COPY_BACK", "1", 1);
    expect("the environment allows it", 1);
    dirs(NULL, "person-no");
    setenv("MEDIA_GPU_ROUTE_COPY_BACK", "sometimes", 1);
    expect("an unreadable environment value leaves the files", 0);

    /* A caller that copies back keeps software when nobody allowed it, for a
     * profile any GPU decodes and even with no GPU at all. */
    dirs(NULL, NULL);
    struct media_gpu_video video = { .codec = MEDIA_GPU_CODEC_H264, .profile = 100, .bits = 8,
        .components = 3, .log2_chroma_w = 1, .log2_chroma_h = 1, .width = 1920, .height = 1080 };
    struct media_gpu_decoder decoder;
    memset(&decoder, 0x55, sizeof(decoder));
    int copy = media_gpu_route_decoder(&video, &decoder);
    int clean = decoder.backend == MEDIA_GPU_SOFTWARE && !decoder.device[0];
    printf("%-58s result=%d %s\n", "copy-back caller, not allowed: software", copy, copy == 0 && clean ? "ok" : "FAIL");
    failures += copy != 0 || !clean;
    copy = media_gpu_route_decoder_frames(&video, MEDIA_GPU_FRAMES_COPY, &decoder);
    printf("%-58s result=%d %s\n", "explicit copy frames, not allowed: software", copy, copy == 0 ? "ok" : "FAIL");
    failures += copy != 0;
    printf("%s\n", failures ? "FAILED" : "PASSED");
    return failures != 0;
}
