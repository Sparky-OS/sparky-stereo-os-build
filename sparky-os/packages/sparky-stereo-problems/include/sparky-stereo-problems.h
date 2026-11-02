/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * libsparky-stereo-problems: the engine that keeps what failed, why and what to do until it is repaired (ORDER 350).
 * The same engine as the command sparky-stereo-problems (sparky-stereo-problems --help says what each verb does).
 *
 * A problem belongs to a PACKAGE (a Debian package name) and has a KEY, unique in that package. MESSAGE is one of the
 * package's own messages (a key of its Sparky language files, built into journal message catalogs); ARGS fill its %s
 * in order, and an argument written "@KEY" is the package's message KEY. Messages are said in the person's language
 * (LANGUAGE, LC_ALL, LC_MESSAGES, LANG, /etc/default/locale), else English.
 *
 * DETAILS, where taken, is NULL or a JSON object with any of:
 *   "severity": "failed" | "degraded" | "notice"     (failed when not given)
 *   "command": ["argv0", ...], "status": N, "output": "the end of its output"   the evidence
 *   "repair": [["argv0", ...], ...]                  run in order by ssp_repair; all must succeed
 *   "actions": [{"id": "...", "label": ["MESSAGE", "ARG"...], "command": ["argv0", ...]}]   offered as buttons
 *   "unit": "name.service"                           a systemd unit: the problem is over when it is not failed
 *   "args": ["text", "@KEY", ["MESSAGE", "ARG"...]]  the arguments, when one is a message with its own arguments
 *   "more": ["@KEY", ["MESSAGE", "ARG"...]]          further sentences after the message (why, what to do)
 *   "data": {...}                                    the package's own fields, kept and returned as they are
 *   "first": "2026-11-02T10:00:00Z"                  for a problem moved from an older store: when it was found
 *
 * MESSAGE is a key of the package's Sparky language files (LOCAL12), or, for a program translated with gettext, its
 * message as CONTEXT|MSGID ("@info|The GPU %1 is not here."), whose %1 .. %26 are its arguments.
 *
 * Calls return 0 when done, 1 when what was asked failed (ssp_error says what, in the person's language;
 * ssp_error_en in English) and 2 for wrong arguments. Text a call returns is freed with ssp_free.
 */
#ifndef SPARKY_STEREO_PROBLEMS_H
#define SPARKY_STEREO_PROBLEMS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Where a problem is kept: the machine's (/var/lib, until repaired), this boot's (/run), the person's own
 * ($XDG_STATE_HOME); SSP_DEFAULT is the machine's for root and the person's otherwise */
#define SSP_DEFAULT (-1)
#define SSP_MACHINE 0
#define SSP_BOOT 1
#define SSP_PERSON 2

/* Keeps a problem; kept again with the same message it keeps its first time and its hide */
int ssp_keep(int scope, const char *package, const char *key, const char *message, const char *const *args, int nargs,
             const char *details);

/* Runs COMMAND with its output on standard error: a success clears KEY, a failure keeps it with the command, its
 * exit status and the end of its output (MESSAGE's first two %s are the command and its status, then ARGS). Returns
 * the command's exit status, or -1 when the problem could not be kept */
int ssp_run(int scope, const char *package, const char *key, const char *message, const char *const *args, int nargs,
            const char *const *command, int ncommand, const char *details);

/* The step works again */
int ssp_clear(int scope, const char *package, const char *key);

/* Every problem of PACKAGE goes from each store the caller can write: its package was removed (its postrm) */
int ssp_clear_all(const char *package);

/* Says MESSAGE on standard error (and in English when the person's language is another) and in the journal */
int ssp_say(const char *package, const char *message, const char *const *args, int nargs);

/* Runs the problem's repair commands: 0 and the problem is over, or the failing command's exit status (the problem
 * shows again where it was hidden), or -1 */
int ssp_repair(int scope, const char *package, const char *key);

/* The person's own view: hidden until its message changes or a repair fails; shown again */
int ssp_hide(int scope, const char *package, const char *key);
int ssp_show(int scope, const char *package, const char *key);

/* Every kept problem (of PACKAGE, or all when NULL) as a JSON array, oldest first, with "title", "text", "lang",
 * "hidden" and "labels" (the actions' labels) in LANG (a LANGUAGE-style list) or the person's languages when NULL */
char *ssp_list_json(const char *package, const char *lang);

/* MESSAGE of PACKAGE as JSON {"title", "text", "lang"} */
char *ssp_render(const char *package, const char *message, const char *const *args, int nargs, const char *lang);

/* The journal MESSAGE_ID of MESSAGE of PACKAGE (32 hexadecimal digits) */
char *ssp_message_id(const char *package, const char *message);

/* The person's languages, most wanted first, separated by ":" (English, always last, is not listed) */
char *ssp_languages(void);

const char *ssp_error(void);
const char *ssp_error_en(void);
void ssp_free(void *text);

#ifdef __cplusplus
}
#endif

#endif
