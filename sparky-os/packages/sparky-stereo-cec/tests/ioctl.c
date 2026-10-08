/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 * SPDX-License-Identifier: GPL-3.0-or-later */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <linux/cec.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static unsigned flags(void)
{
    unsigned value = 0;
    FILE *file = fopen(getenv("CEC_TEST_STATE"), "r");
    if (file) {
        fscanf(file, "%u", &value);
        fclose(file);
    }
    return value;
}

static void set_flags(unsigned value)
{
    FILE *file = fopen(getenv("CEC_TEST_STATE"), "w");
    if (file) {
        fprintf(file, "%u\n", value);
        fclose(file);
    }
}

int ioctl(int fd, unsigned long request, ...)
{
    va_list arguments;
    va_start(arguments, request);
    void *arg = va_arg(arguments, void *);
    va_end(arguments);
    char proc[64], path[4096];
    snprintf(proc, sizeof(proc), "/proc/self/fd/%d", fd);
    const ssize_t size = readlink(proc, path, sizeof(path) - 1);
    if (size >= 0) {
        path[size] = 0;
    }
    const char *root = getenv("CEC_TEST_DEVICES");
    if (!root || size < 0 || strncmp(path, root, strlen(root)) || !strstr(path, "/cec")) {
        int (*real_ioctl)(int, unsigned long, ...) = dlsym(RTLD_NEXT, "ioctl");
        return real_ioctl(fd, request, arg);
    }
    const unsigned value = flags();
    switch (request) {
    case CEC_ADAP_G_CAPS: {
        struct cec_caps *caps = arg;
        memset(caps, 0, sizeof(*caps));
        strcpy(caps->driver, "test-cec");
        strcpy(caps->name, "Synthetic CEC adapter");
        caps->available_log_addrs = value & 256 ? 2 : 1;
        caps->capabilities = CEC_CAP_LOG_ADDRS | CEC_CAP_TRANSMIT | CEC_CAP_PHYS_ADDR | CEC_CAP_CONNECTOR_INFO;
        if (value & 4) {
            caps->capabilities &= ~CEC_CAP_TRANSMIT;
        }
        if (value & 8) {
            caps->capabilities &= ~CEC_CAP_LOG_ADDRS;
        }
        if (value & 32) {
            caps->capabilities &= ~CEC_CAP_CONNECTOR_INFO;
        }
        caps->version = (6 << 16) | (17 << 8);
        return 0;
    }
    case CEC_ADAP_G_CONNECTOR_INFO: {
        struct cec_connector_info *info = arg;
        memset(info, 0, sizeof(*info));
        info->type = CEC_CONNECTOR_TYPE_DRM;
        info->drm.card_no = 0;
        info->drm.connector_id = 99;
        return 0;
    }
    case CEC_ADAP_G_PHYS_ADDR:
        *(__u16 *)arg = value & 1 ? CEC_PHYS_ADDR_INVALID : 0x1000;
        return 0;
    case CEC_ADAP_S_PHYS_ADDR:
        set_flags(*(__u16 *)arg == CEC_PHYS_ADDR_INVALID ? value | 1 : value & ~1U);
        return 0;
    case CEC_ADAP_G_LOG_ADDRS: {
        struct cec_log_addrs *addresses = arg;
        memset(addresses, 0, sizeof(*addresses));
        if (!(value & 2)) {
            addresses->num_log_addrs = 1;
            addresses->log_addr[0] = value & 16 ? CEC_LOG_ADDR_TV : CEC_LOG_ADDR_PLAYBACK_1;
            addresses->log_addr_mask = 1U << addresses->log_addr[0];
            addresses->primary_device_type[0] = value & 16 ? CEC_OP_PRIM_DEVTYPE_TV : CEC_OP_PRIM_DEVTYPE_PLAYBACK;
            if (value & 256) {
                addresses->num_log_addrs = 2;
                addresses->log_addr[0] = CEC_LOG_ADDR_TV;
                addresses->log_addr[1] = CEC_LOG_ADDR_PLAYBACK_1;
                addresses->log_addr_mask = 0x11;
            }
        }
        return 0;
    }
    case CEC_ADAP_S_LOG_ADDRS: {
        struct cec_log_addrs *addresses = arg;
        if (value & 8) {
            errno = EPERM;
            return -1;
        }
        set_flags(addresses->num_log_addrs ? value & ~2U : value | 2);
        addresses->log_addr[0] = CEC_LOG_ADDR_PLAYBACK_1;
        addresses->log_addr_mask = 1U << CEC_LOG_ADDR_PLAYBACK_1;
        return 0;
    }
    case CEC_TRANSMIT: {
        struct cec_msg *message = arg;
        FILE *file = fopen(getenv("CEC_TEST_FRAMES"), "a");
        if (file) {
            for (unsigned i = 0; i < message->len; i++) {
                fprintf(file, "%02x", message->msg[i]);
            }
            fprintf(file, "\n");
            fclose(file);
        }
        if (value & 128) {
            usleep(250000);
        }
        if (value & 512) {
            usleep(12000000);
        }
        message->sequence = 1;
        const int nack = (value & 64) || ((value & 16384) && message->msg[1] == CEC_MSG_STANDBY)
            || ((value & 32768) && message->msg[1] == CEC_MSG_IMAGE_VIEW_ON);
        message->tx_status = nack ? CEC_TX_STATUS_NACK | CEC_TX_STATUS_MAX_RETRIES : CEC_TX_STATUS_OK;
        message->tx_nack_cnt = nack ? 4 : 0;
        if (message->msg[1] == CEC_MSG_REQUEST_ACTIVE_SOURCE && message->reply == CEC_MSG_ACTIVE_SOURCE && !(value & 64)) {
            message->rx_status = value & 2048 ? CEC_RX_STATUS_TIMEOUT : value & 4096 ? CEC_RX_STATUS_FEATURE_ABORT : CEC_RX_STATUS_OK;
            if (!(value & 2048)) {
                message->len = 4;
                message->msg[0] = 0x8f;
                message->msg[1] = value & 4096 ? CEC_MSG_FEATURE_ABORT : CEC_MSG_ACTIVE_SOURCE;
                message->msg[2] = value & 1024 ? 0x20 : 0x10;
                message->msg[3] = 0;
            }
        }
        return 0;
    }
    case CEC_S_MODE:
        return 0;
    default:
        errno = ENOTTY;
        return -1;
    }
}
