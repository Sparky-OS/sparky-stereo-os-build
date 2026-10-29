/* SPDX-License-Identifier: MIT */
/* Native GLX control for the Wine offscreen-child resize witness. */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xcomposite.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <GL/glxext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static unsigned long long ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return (unsigned long long)t.tv_sec*1000000000+t.tv_nsec; }
static void save(const char *phase,const char *buffer,const void *bytes,size_t count) { char path[256]; snprintf(path,sizeof(path),"%s-%s.raw",phase,buffer); FILE *f=fopen(path,"wx"); if(!f || fwrite(bytes,1,count,f)!=count)exit(8); fclose(f); }

static void check(const char *phase, const char *buffer, GLenum target, int w, int h)
{
    unsigned char *p = calloc(w*h,3);
    unsigned errors = 0;
    glReadBuffer(target); glReadPixels(0,0,w,h,GL_RGB,GL_UNSIGNED_BYTE,p);
    for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
        unsigned char *v=p+3*(y*w+x);
        if(v[0]!=x || v[1]!=y || v[2]!=0) errors++;
    }
    printf("NATIVE phase=%s buffer=%s size=%dx%d errors=%u first=%u,%u,%u last=%u,%u,%u gl_error=%u\n",phase,buffer,w,h,errors,p[0],p[1],p[2],p[3*(w*h-1)],p[3*(w*h-1)+1],p[3*(w*h-1)+2],glGetError());
    save(phase,buffer,p,w*h*3);
    free(p);
}
static void frame(Display *d, Window child, GLXWindow drawable, const char *phase, int w,int h)
{
    XWindowAttributes a; XGetWindowAttributes(d,child,&a);
    printf("BEGIN phase=%s ns=%llu child=%lu drawable=%lu requested=%dx%d xsize=%dx%d\n",phase,ns(),child,drawable,w,h,a.width,a.height);
    unsigned char *p=calloc(w*h,3);
    PFNGLXSWAPBUFFERSMSCOMLPROC swap=(void*)glXGetProcAddressARB((const GLubyte*)"glXSwapBuffersMscOML");
    PFNGLXWAITFORSBCOMLPROC wait=(void*)glXGetProcAddressARB((const GLubyte*)"glXWaitForSbcOML");
    int64_t ust=0,msc=0,sbc=0,target;
    glViewport(0,0,w,h);glMatrixMode(GL_PROJECTION);glLoadIdentity();glOrtho(0,w,0,h,-1,1);glMatrixMode(GL_MODELVIEW);glLoadIdentity();
    glDisable(GL_DITHER);glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_UNPACK_ALIGNMENT,1);
    for(int y=0;y<h;y++) for(int x=0;x<w;x++){p[3*(y*w+x)]=x;p[3*(y*w+x)+1]=y;}
    glDrawBuffer(GL_BACK);glRasterPos2i(0,0);glDrawPixels(w,h,GL_RGB,GL_UNSIGNED_BYTE,p);free(p);
    check(phase,"back",GL_BACK,w,h);
    glFlush();printf("SWAP_BEGIN phase=%s ns=%llu\n",phase,ns());fflush(stdout);target=swap(d,drawable,0,0,0);
    printf("SWAP_RETURN phase=%s ns=%llu target=%lld\n",phase,ns(),(long long)target);
    int ret=wait(d,drawable,target,&ust,&msc,&sbc);
    printf("WAIT phase=%s ns=%llu target=%lld ret=%d ust=%lld msc=%lld sbc=%lld\n",phase,ns(),(long long)target,ret,(long long)ust,(long long)msc,(long long)sbc);
    check(phase,"front",GL_FRONT,w,h);
    XImage *image=XGetImage(d,child,0,0,w,h,AllPlanes,ZPixmap);
    unsigned errors=0;
    if(!image)exit(5);
    for(int y=0;y<h;y++) for(int x=0;x<w;x++)
        if((XGetPixel(image,x,y)&0xffffff)!=((unsigned)x<<16 | (unsigned)(h-y-1)<<8))errors++;
    printf("NATIVE phase=%s buffer=x-window size=%dx%d errors=%u first=%06lx\n",phase,w,h,errors,XGetPixel(image,0,0)&0xffffff);
    save(phase,"x-window",image->data,image->bytes_per_line*image->height);
    printf("XFORMAT phase=%s stride=%d bpp=%d byte_order=%d masks=%lx,%lx,%lx\n",phase,image->bytes_per_line,image->bits_per_pixel,image->byte_order,image->red_mask,image->green_mask,image->blue_mask);
    XDestroyImage(image);fflush(stdout);
}
int main(void)
{
    Display *d=XOpenDisplay(NULL);int count;XVisualInfo *visual;
    int attr[]={GLX_X_RENDERABLE,True,GLX_DRAWABLE_TYPE,GLX_WINDOW_BIT,GLX_RENDER_TYPE,GLX_RGBA_BIT,GLX_DOUBLEBUFFER,True,GLX_RED_SIZE,8,GLX_GREEN_SIZE,8,GLX_BLUE_SIZE,8,None};
    if(!d)return 1;
    GLXFBConfig *configs=glXChooseFBConfig(d,DefaultScreen(d),attr,&count);if(!configs||!count)return 2;
    GLXFBConfig cfg=configs[0];visual=glXGetVisualFromFBConfig(d,cfg);if(!visual)return 3;
    XSetWindowAttributes a={0};a.colormap=XCreateColormap(d,DefaultRootWindow(d),visual->visual,AllocNone);
    Window parent=XCreateSimpleWindow(d,DefaultRootWindow(d),0,0,1,1,0,0,0);
    Window child=XCreateWindow(d,parent,0,0,240,140,0,visual->depth,InputOutput,visual->visual,CWColormap,&a);
    XMapWindow(d,parent);XMapWindow(d,child);XSync(d,False);
    GLXWindow drawable=glXCreateWindow(d,cfg,child,NULL);
    XCompositeRedirectWindow(d,child,CompositeRedirectManual);XSync(d,False);
    GLXContext ctx=glXCreateNewContext(d,cfg,GLX_RGBA_TYPE,NULL,True);if(!ctx||!glXMakeCurrent(d,drawable,ctx))return 4;
    printf("RENDERER %s\n",glGetString(GL_RENDERER));
    frame(d,child,drawable,"initial",240,140);
    XResizeWindow(d,child,200,120);XSync(d,False);
    frame(d,child,drawable,"first-resize",200,120);frame(d,child,drawable,"second-resize",200,120);
    XUnmapWindow(d,child);XSync(d,False);XMapWindow(d,child);XSync(d,False);
    frame(d,child,drawable,"show",200,120);
    FILE *maps=fopen("/proc/self/maps","r");char line[2048];while(fgets(line,sizeof(line),maps))if(strstr(line,"/"))printf("MAP %s",line);fclose(maps);
    glXMakeCurrent(d,None,NULL);glXDestroyContext(d,ctx);glXDestroyWindow(d,drawable);XDestroyWindow(d,parent);XFree(visual);XFree(configs);XCloseDisplay(d);return 0;
}
