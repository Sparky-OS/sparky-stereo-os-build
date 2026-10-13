/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#ifndef GL_STEREO_SUPPORT_VERSION
#define GL_STEREO_SUPPORT_VERSION 2
#endif
int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    Display *d = XOpenDisplay(NULL);
    if (!d) return 2;
    unsigned long version = GL_STEREO_SUPPORT_VERSION;
    Atom a = XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT_SUPPORTED",False);
    XChangeProperty(d,DefaultRootWindow(d),a,XA_CARDINAL,32,PropModeReplace,(unsigned char *)&version,1);
    XSync(d,False);
    pid_t child = fork();
    if (child == 0) { close(ConnectionNumber(d)); execvp(argv[1],argv+1); perror(argv[1]); _exit(127); }
    if (child < 0) return 2;
    int status;
    if (waitpid(child,&status,0) < 0) return 2;
    XDeleteProperty(d,DefaultRootWindow(d),a); XCloseDisplay(d);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128+WTERMSIG(status);
}
