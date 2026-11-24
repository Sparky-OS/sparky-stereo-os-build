/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <stdio.h>
#include <stereo-policy.h>

/* Feed the installed layer's words to xgettext without maintaining another list. */
int main(void)
{
    for (size_t i = 0; i < stereo_policy_input_format_count(); ++i) {
        const char *text = stereo_policy_input_format_at(i)->text;
        fputs("i18n(\"", stdout);
        for (; *text; ++text) {
            if (*text == '\\' || *text == '"') putchar('\\');
            if (*text == '\n') fputs("\\n", stdout);
            else putchar(*text);
        }
        puts("\");");
    }
    return ferror(stdout) ? 1 : 0;
}
