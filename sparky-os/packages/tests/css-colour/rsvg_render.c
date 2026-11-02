/* ORDER 348 measurement: renders the corpus with librsvg into cairo image surfaces (RGBA128F, the deepest cairo has,
 * and ARGB32) and prints the stored values as JSON lines, with what librsvg logged (GLib messages and its
 * RSVG_LOG output on stderr) for that render.
 * Usage: RSVG_LOG=1 rsvg_render CORPUS_DIR CASES_LIST > results.jsonl
 * CASES_LIST: lines "id width height x1,y1;x2,y2;..." (rsvg_cases.py writes it from cases.json); a line starting
 * with "P " is a precision fixture: "P id width height". */
#include <cairo.h>
#include <librsvg/rsvg.h>
#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static GString *messages;

static void log_handler(const gchar *domain, GLogLevelFlags level, const gchar *msg, gpointer data)
{
    (void)level;
    (void)data;
    g_string_append_printf(messages, "%s%s: %s\n", messages->len ? "" : "", domain ? domain : "glib", msg);
}

static void json_string(const char *s)
{
    putchar('"');
    for (; *s; ++s) {
        if (*s == '"' || *s == '\\')
            printf("\\%c", *s);
        else if (*s == '\n')
            printf("\\n");
        else if ((unsigned char)*s < 0x20)
            printf("\\u%04x", *s);
        else
            putchar(*s);
    }
    putchar('"');
}

static cairo_surface_t *render(const char *path, int w, int h, cairo_format_t fmt, char **err_out)
{
    cairo_surface_t *s = cairo_image_surface_create(fmt, w, h);
    cairo_t *cr = cairo_create(s);
    GError *error = NULL;
    /* capture stderr (librsvg's RSVG_LOG output) for this render */
    const char *tmpdir = getenv("RSVG_RENDER_TMP");
    char path_tmp[512];
    snprintf(path_tmp, sizeof path_tmp, "%s/rsvg-render-XXXXXX", tmpdir ? tmpdir : "/tmp");
    int fd = mkstemp(path_tmp);
    fflush(stdout);
    fflush(stderr);
    int saved = dup(2), saved1 = dup(1);
    dup2(fd, 2);
    dup2(fd, 1);
    RsvgHandle *handle = rsvg_handle_new_from_file(path, &error);
    if (handle) {
        RsvgRectangle viewport = {0, 0, w, h};
        if (!rsvg_handle_render_document(handle, cr, &viewport, &error) && error)
            g_string_append_printf(messages, "render: %s\n", error->message);
        g_object_unref(handle);
    } else if (error) {
        g_string_append_printf(messages, "load: %s\n", error->message);
    }
    g_clear_error(&error);
    fflush(stdout);
    fflush(stderr);
    dup2(saved, 2);
    dup2(saved1, 1);
    close(saved);
    close(saved1);
    lseek(fd, 0, SEEK_SET);
    /* keep only librsvg's warnings, not RSVG_LOG's drawing trace */
    GString *keep = g_string_new(NULL);
    FILE *in = fdopen(fd, "r");
    char l[8192];
    while (fgets(l, sizeof l, in)) {
        if (strstr(l, "rror") || strstr(l, "arning") || strstr(l, "nvalid") || strstr(l, "olor") || strstr(l, "gamut")
            || strstr(l, "nsupported"))
            g_string_append(keep, l);
    }
    fclose(in);
    unlink(path_tmp);
    *err_out = g_string_free(keep, FALSE);
    cairo_destroy(cr);
    cairo_surface_flush(s);
    return s;
}

/* stored values at (x, y), un-premultiplied, as floats in R, G, B, A order */
static void pixel(cairo_surface_t *s, int x, int y, double out[4])
{
    unsigned char *data = cairo_image_surface_get_data(s);
    int stride = cairo_image_surface_get_stride(s);
    if (cairo_image_surface_get_format(s) == CAIRO_FORMAT_RGBA128F) {
        float *p = (float *)(data + y * stride) + 4 * x;
        double a = p[3];
        for (int i = 0; i < 3; ++i)
            out[i] = a > 0 ? p[i] / a : 0.0;
        out[3] = a;
    } else {
        uint32_t v = ((uint32_t *)(data + y * stride))[x];
        double a = ((v >> 24) & 255) / 255.0;
        out[0] = a > 0 ? (((v >> 16) & 255) / 255.0) / a : 0.0;
        out[1] = a > 0 ? (((v >> 8) & 255) / 255.0) / a : 0.0;
        out[2] = a > 0 ? ((v & 255) / 255.0) / a : 0.0;
        out[3] = a;
    }
}

int main(int argc, char **argv)
{
    const char *dir = argv[1];
    FILE *list = fopen(argv[2], "r");
    char line[4096];
    messages = g_string_new(NULL);
    g_log_set_default_handler(log_handler, NULL);
    printf("{\"librsvg_version\": \"%d.%d.%d\", \"cairo_version\": \"%s\"}\n", LIBRSVG_MAJOR_VERSION,
           LIBRSVG_MINOR_VERSION, LIBRSVG_MICRO_VERSION, cairo_version_string());
    struct { cairo_format_t f; const char *name; } fmts[] = {{CAIRO_FORMAT_RGBA128F, "RGBA128F"}, {CAIRO_FORMAT_ARGB32, "ARGB32"}};
    while (fgets(line, sizeof line, list)) {
        char id[1024], pts[3000];
        int w, h;
        int precision = line[0] == 'P';
        if (precision) {
            if (sscanf(line + 2, "%1023s %d %d", id, &w, &h) != 3)
                continue;
        } else if (sscanf(line, "%1023s %d %d %2999s", id, &w, &h, pts) != 4) {
            continue;
        }
        char path[2048];
        snprintf(path, sizeof path, "%s/svg/%s.svg", dir, id);
        for (unsigned k = 0; k < sizeof fmts / sizeof fmts[0]; ++k) {
            g_string_truncate(messages, 0);
            char *err = NULL;
            cairo_surface_t *s = render(path, w, h, fmts[k].f, &err);
            g_string_append(messages, err);
            g_free(err);
            if (precision) {
                /* distinct green values along row 1 */
                GHashTable *seen = g_hash_table_new(g_double_hash, g_double_equal);
                double *vals = g_new(double, w);
                for (int x = 0; x < w; ++x) {
                    double px[4];
                    pixel(s, x, 1, px);
                    vals[x] = px[1];
                    g_hash_table_add(seen, &vals[x]);
                }
                printf("{\"precision\": \"%s\", \"target\": \"rsvg:%s:none\", \"distinct\": %u, \"sample\": [", id,
                       fmts[k].name, g_hash_table_size(seen));
                for (int x = 0; x < w; x += 64)
                    printf("%s%.9g", x ? ", " : "", vals[x]);
                printf("], \"messages\": ");
                g_hash_table_destroy(seen);
                g_free(vals);
            } else {
                printf("{\"id\": \"%s\", \"target\": \"rsvg:%s:none\", \"pixels\": [", id, fmts[k].name);
                char *save = NULL;
                char *copy = g_strdup(pts);
                int first = 1;
                for (char *tok = strtok_r(copy, ";", &save); tok; tok = strtok_r(NULL, ";", &save)) {
                    int x, y;
                    if (sscanf(tok, "%d,%d", &x, &y) != 2)
                        continue;
                    double px[4];
                    pixel(s, x, y, px);
                    printf("%s[%.9g, %.9g, %.9g, %.9g]", first ? "" : ", ", px[0], px[1], px[2], px[3]);
                    first = 0;
                }
                g_free(copy);
                printf("], \"messages\": ");
            }
            /* messages as a JSON list of lines */
            printf("[");
            gchar **lines = g_strsplit(messages->str, "\n", -1);
            int firstm = 1;
            for (gchar **l = lines; *l; ++l) {
                if (!**l)
                    continue;
                printf("%s", firstm ? "" : ", ");
                json_string(*l);
                firstm = 0;
            }
            g_strfreev(lines);
            printf("]}\n");
            cairo_surface_destroy(s);
        }
    }
    fclose(list);
    return 0;
}
