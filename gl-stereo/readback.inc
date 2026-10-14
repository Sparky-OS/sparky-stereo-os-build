/* SPDX-License-Identifier: GPL-2.0-or-later */
/* CPU consumers must see the same multisample resolve as the window system.
 * This runs only for explicit diagnostic/stream readback, never presentation. */
static void read_window_color(int width, int height, GLenum format, void *pixels)
{
    GLint draw, renderbuffer, samples;
    r_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&draw);
    r_glGetIntegerv(GL_RENDERBUFFER_BINDING,&renderbuffer);
    r_glBindFramebuffer(GL_DRAW_FRAMEBUFFER,0);
    r_glGetIntegerv(GL_SAMPLES,&samples);
    r_glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw);
    if (samples <= 1) {
        r_glReadPixels(0,0,width,height,format,GL_UNSIGNED_BYTE,pixels);
        return;
    }
    GLint read; GLuint framebuffer, color;
    r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&read);
    GLboolean scissor=r_glIsEnabled(GL_SCISSOR_TEST);
    GLboolean srgb=r_glIsEnabled(GL_FRAMEBUFFER_SRGB);
    r_glGenFramebuffers(1,&framebuffer);
    r_glGenRenderbuffers(1,&color);
    r_glBindRenderbuffer(GL_RENDERBUFFER,color);
    r_glRenderbufferStorage(GL_RENDERBUFFER,GL_RGBA8,width,height);
    r_glBindFramebuffer(GL_DRAW_FRAMEBUFFER,framebuffer);
    r_glFramebufferRenderbuffer(GL_DRAW_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,color);
    r_glDisable(GL_SCISSOR_TEST);
    r_glDisable(GL_FRAMEBUFFER_SRGB);
    r_glBlitFramebuffer(0,0,width,height,0,0,width,height,GL_COLOR_BUFFER_BIT,GL_NEAREST);
    r_glBindFramebuffer(GL_READ_FRAMEBUFFER,framebuffer);
    r_glReadPixels(0,0,width,height,format,GL_UNSIGNED_BYTE,pixels);
    r_glBindFramebuffer(GL_READ_FRAMEBUFFER,read);
    r_glBindFramebuffer(GL_DRAW_FRAMEBUFFER,draw);
    r_glBindRenderbuffer(GL_RENDERBUFFER,renderbuffer);
    if (scissor) r_glEnable(GL_SCISSOR_TEST);
    if (srgb) r_glEnable(GL_FRAMEBUFFER_SRGB);
    r_glDeleteFramebuffers(1,&framebuffer);
    r_glDeleteRenderbuffers(1,&color);
}
