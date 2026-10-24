/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* KConfig's reading of a boolean entry: true, on, yes or a non-zero number. */
static int parse_bool(const char *text, int *value)
{
    static const char *const yes[] = { "true", "on", "yes", "1" };
    static const char *const no[] = { "false", "off", "no", "0" };
    for (size_t i = 0; i < sizeof(yes) / sizeof(yes[0]); i++) {
        if (!strcasecmp(text, yes[i])) {
            *value = 1;
            return 1;
        }
        if (!strcasecmp(text, no[i])) {
            *value = 0;
            return 1;
        }
    }
    return 0;
}

static char *trim(char *text)
{
    while (isspace((unsigned char)*text))
        text++;
    char *end = text + strlen(text);
    while (end > text && isspace((unsigned char)end[-1]))
        *--end = 0;
    return text;
}

/* Read one boolean entry of a KConfig file. A group or key carrying KConfig's
 * [$i] mark is read like any other; localized keys (Key[xx]) are not ours. */
int media_gpu_read_bool(const char *path, const char *group, const char *key, int *value)
{
    FILE *file = fopen(path, "re");
    if (!file)
        return 0;
    char line[512];
    int in_group = 0, found = 0;
    while (fgets(line, sizeof(line), file)) {
        char *text = trim(line);
        if (!*text || *text == '#')
            continue;
        if (*text == '[') {
            char *close = strchr(text, ']');
            in_group = close && (size_t)(close - text - 1) == strlen(group)
                && !strncmp(text + 1, group, strlen(group));
            continue;
        }
        if (!in_group)
            continue;
        char *equals = strchr(text, '=');
        if (!equals)
            continue;
        *equals = 0;
        char *name = trim(text);
        char *mark = strstr(name, "[$");
        if (mark)
            *mark = 0;
        if (strcmp(trim(name), key))
            continue;
        int parsed;
        if (parse_bool(trim(equals + 1), &parsed)) {
            *value = parsed;
            found = 1;
        }
    }
    fclose(file);
    return found;
}

static void read_config_dir(const char *dir, size_t length, int *value)
{
    char path[1024];
    if (length && snprintf(path, sizeof(path), "%.*s/sparky-stereo-graphicsrc", (int)length, dir) < (int)sizeof(path))
        media_gpu_read_bool(path, "Decoding", "CopyBack", value);
}

int media_gpu_route_copy_back(void)
{
    int value = 0;
    const char *env = getenv("MEDIA_GPU_ROUTE_COPY_BACK");
    if (env && parse_bool(env, &value))
        return value;
    /* $XDG_CONFIG_DIRS lists the most important directory first, so read it
     * last; the person's own file comes after every system file. */
    const char *dirs = getenv("XDG_CONFIG_DIRS");
    if (!dirs || !*dirs)
        dirs = "/etc/xdg";
    const char *end = dirs + strlen(dirs);
    while (end > dirs) {
        const char *start = end;
        while (start > dirs && start[-1] != ':')
            start--;
        read_config_dir(start, (size_t)(end - start), &value);
        end = start > dirs ? start - 1 : dirs;
    }
    const char *home = getenv("XDG_CONFIG_HOME");
    char user[1024];
    if (home && *home)
        read_config_dir(home, strlen(home), &value);
    else if ((home = getenv("HOME")) && *home
             && snprintf(user, sizeof(user), "%s/.config", home) < (int)sizeof(user))
        read_config_dir(user, strlen(user), &value);
    return value;
}
