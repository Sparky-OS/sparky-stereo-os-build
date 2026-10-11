// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#define _GNU_SOURCE
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

static const size_t bytes = 16 * 1024 * 1024;
static pthread_barrier_t barrier;
static int failed;

static double seconds(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void *touch(void *unused)
{
    (void)unused;
    volatile unsigned char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    pthread_barrier_wait(&barrier);
    if (p == MAP_FAILED) {
        __atomic_store_n(&failed, 1, __ATOMIC_RELAXED);
        return NULL;
    }
    // Touch fresh base pages; huge pages would hide the page-fault cost.
    madvise((void *)p, bytes, MADV_NOHUGEPAGE);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    for (size_t i = 0; i < bytes; i += page)
        p[i] = 1;
    munmap((void *)p, bytes);
    return NULL;
}

static uint64_t hash(uint64_t h, const char *s)
{
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= UINT64_C(1099511628211);
    }
    return h;
}

static int fingerprint(void)
{
    struct utsname u;
    if (uname(&u) < 0)
        return 1;
    uint64_t h = hash(UINT64_C(14695981039346656037), u.release);
    char line[4096];
    const char *files[] = {"/proc/cpuinfo", "/proc/meminfo", "/sys/devices/system/cpu/online"};
    for (size_t i = 0; i < sizeof(files) / sizeof(files[0]); ++i) {
        FILE *f = fopen(files[i], "r");
        if (!f)
            return 1;
        while (fgets(line, sizeof(line), f)) {
            if (i == 0 && strncmp(line, "model name", 10) && strncmp(line, "flags", 5)
                && strncmp(line, "microcode", 9) && strncmp(line, "processor", 9))
                continue;
            if (i == 1 && strncmp(line, "MemTotal:", 9))
                continue;
            h = hash(h, line);
        }
        fclose(f);
    }
    // Firmware memory records also distinguish equal-capacity replacements.
    FILE *dmi = fopen("/sys/firmware/dmi/tables/DMI", "rb");
    if (dmi) {
        int c;
        while ((c = fgetc(dmi)) != EOF) {
            h ^= (unsigned char)c;
            h *= UINT64_C(1099511628211);
        }
        fclose(dmi);
    }
    printf("%016" PRIx64 "\n", h);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--fingerprint"))
        return fingerprint();
    if (argc != 1)
        return 2;
    cpu_set_t affinity;
    if (sched_getaffinity(0, sizeof(affinity), &affinity) < 0)
        return 1;
    int cpus = CPU_COUNT(&affinity);
    int workers = cpus < 4 ? cpus : 4;
    if (workers < 1)
        return 1;
    pthread_t threads[4];
    double best = 0, start = seconds();
    for (int round = 0; round < 3; ++round) {
        pthread_barrier_init(&barrier, NULL, (unsigned)workers + 1);
        for (int i = 0; i < workers; ++i) {
            int rc = pthread_create(&threads[i], NULL, touch, NULL);
            if (rc) {
                fprintf(stderr, "allocation calibration: %s\n", strerror(rc));
                return 1;
            }
        }
        double before = seconds();
        pthread_barrier_wait(&barrier);
        for (int i = 0; i < workers; ++i)
            pthread_join(threads[i], NULL);
        double rate = workers * 16 / (seconds() - before);
        if (rate > best)
            best = rate;
        pthread_barrier_destroy(&barrier);
        if (failed)
            return 1;
        if (seconds() - start > 0.2)
            break;
    }
    // Allow all CPUs to allocate together and a further 2x transient margin.
    printf("%.0f %d %d %.3f\n", best, cpus, workers, seconds() - start);
    return 0;
}
