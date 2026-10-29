/* SPDX-License-Identifier: MIT */
/* Exercise the installed Mesa declaration writer; never write stereo properties. */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <GL/glxext.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
static Display *d;
static unsigned errors,frames;
static int record_error(Display *display,XErrorEvent *event)
{
    (void)display;++errors;printf("XERROR code=%u major=%u minor=%u serial=%lu resource=%lu\n",event->error_code,event->request_code,event->minor_code,event->serial,event->resourceid);return 0;
}
static Window owners[2],children[2];
static void property(Window w,const char *name)
{
    Atom type; int format; unsigned long count,left; unsigned char *data=NULL;
    int rc=XGetWindowProperty(d,w,XInternAtom(d,name,False),0,4096,False,AnyPropertyType,&type,&format,&count,&left,&data);
    printf("PROPERTY window=%lu name=%s rc=%d type=%lu format=%d count=%lu values=",w,name,rc,type,format,count);
    if(format==32)for(unsigned long i=0;i<count;i++)printf("%s%lu",i?",":"",((unsigned long*)data)[i]);
    putchar('\n');if(data)XFree(data);
}
static int owner_has(Window owner, Window first, Window second)
{
    Atom type; int format; unsigned long count,left; unsigned char *data=NULL;
    int rc=XGetWindowProperty(d,owner,XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT_CHILDREN",False),0,4096,False,XA_WINDOW,&type,&format,&count,&left,&data);
    unsigned wanted=(first!=None)+(second!=None);
    int match=rc==Success && !left && count==wanted;
    if(wanted) {
        unsigned long *values=(unsigned long*)data;
        match=match && type==XA_WINDOW && format==32;
        if(match && wanted==1)match=values[0]==first;
        if(match && wanted==2)match=(values[0]==first && values[1]==second)||(values[0]==second && values[1]==first);
    }
    if(data)XFree(data);
    return match;
}
static void snapshot(const char *stage)
{
    XSync(d,False);printf("IMMEDIATE %s\n",stage);
    for(int i=0;i<2;i++){XWindowAttributes a;XGetWindowAttributes(d,owners[i],&a);printf("APP_MASK stage=%s owner=%lu mask=%ld\n",stage,owners[i],a.your_event_mask);}
    for(int i=0;i<2;i++)property(owners[i],"_KDE_NET_WM_STEREO_CONTENT_CHILDREN");
    Window a=children[0],b=children[1],c=None;
    if(strncmp(stage,"reparent",8)==0){a=children[1];b=None;c=children[0];}
    if(!strcmp(stage,"window-destroy-before-next-swap")||!strcmp(stage,"other-child-next-swap")){a=children[1];b=None;}
    if(!strcmp(stage,"both-windows-destroyed")){a=b=None;}
    unsigned poll;
    for(poll=0;poll<200;poll++) {
        if(owner_has(owners[0],a,b) && owner_has(owners[1],c,None))break;
        usleep(5000);
    }
    printf("SETTLED stage=%s polls=%u matched=%d no_swap_during_wait=1\n",stage,poll,poll<200);
    printf("STAGE %s\n",stage);
    for(int i=0;i<2;i++) {property(owners[i],"_KDE_NET_WM_STEREO_CONTENT");property(owners[i],"_KDE_NET_WM_STEREO_CONTENT_CHILDREN");}
    fflush(stdout);
}
static void draw(GLXWindow glx,int index)
{
    GLboolean stereo=False;glGetBooleanv(GL_STEREO,&stereo);if(!stereo)exit(77);
    glDrawBuffer(GL_BACK_LEFT);glClearColor(1,index*.25f,0,1);glClear(GL_COLOR_BUFFER_BIT);
    glDrawBuffer(GL_BACK_RIGHT);glClearColor(0,index*.25f,1,1);glClear(GL_COLOR_BUFFER_BIT);
    glXSwapBuffers(d,glx);glFinish();
    PFNGLXWAITFORSBCOMLPROC wait=(void*)glXGetProcAddressARB((const GLubyte*)"glXWaitForSbcOML");
    int64_t ust,msc,sbc;if(!wait(d,glx,0,&ust,&msc,&sbc))exit(5);
    for(int eye=0;eye<2;eye++) {
        unsigned char pixels[120*100*3];char name[100];
        glReadBuffer(eye?GL_FRONT_RIGHT:GL_FRONT_LEFT);glPixelStorei(GL_PACK_ALIGNMENT,1);glReadPixels(0,0,120,100,GL_RGB,GL_UNSIGNED_BYTE,pixels);
        snprintf(name,sizeof(name),"frame%u-eye%d.rgb",frames,eye);FILE *f=fopen(name,"wx");if(!f || fwrite(pixels,1,sizeof(pixels),f)!=sizeof(pixels))exit(8);fclose(f);
        printf("PIXELS frame=%u eye=%d gl_error=%u first=%u,%u,%u\n",frames,eye,glGetError(),pixels[0],pixels[1],pixels[2]);
    }
    ++frames;
    printf("DRAW child=%lu glx=%lu completed_sbc=%lld\n",children[index],glx,(long long)sbc);
}
int main(void)
{
    int count;d=XOpenDisplay(NULL);if(!d)return 1;XSetErrorHandler(record_error);
    printf("ATOMS content=%lu children=%lu\n",XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT",False),XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT_CHILDREN",False));
    int attr[]={GLX_X_RENDERABLE,True,GLX_DRAWABLE_TYPE,GLX_WINDOW_BIT,GLX_RENDER_TYPE,GLX_RGBA_BIT,GLX_DOUBLEBUFFER,True,GLX_STEREO,True,None};
    GLXFBConfig *configs=glXChooseFBConfig(d,DefaultScreen(d),attr,&count);if(!configs||!count)return 77;
    XVisualInfo *v=glXGetVisualFromFBConfig(d,configs[0]);if(!v)return 2;
    XSetWindowAttributes a={0};a.colormap=XCreateColormap(d,DefaultRootWindow(d),v->visual,AllocNone);
    for(int i=0;i<2;i++) {
        owners[i]=XCreateSimpleWindow(d,DefaultRootWindow(d),20+i*350,20,320,260,0,0,0x204060);
        XStoreName(d,owners[i],i?"Native owner B":"Native owner A");XMapWindow(d,owners[i]);
        children[i]=XCreateWindow(d,owners[0],10+i*140,50,120,100,0,v->depth,InputOutput,v->visual,CWColormap,&a);XMapWindow(d,children[i]);
    }
    XSync(d,False);printf("IDS ownerA=%lu ownerB=%lu childA=%lu childB=%lu\n",owners[0],owners[1],children[0],children[1]);
    GLXContext ctx=glXCreateNewContext(d,configs[0],GLX_RGBA_TYPE,NULL,True);if(!ctx)return 3;
    GLXWindow glx[2];
    for(int i=0;i<2;i++){glx[i]=glXCreateWindow(d,configs[0],children[i],NULL);if(!glXMakeCurrent(d,glx[i],ctx))return 4;draw(glx[i],i);}
    snapshot("two-children");
    glXMakeCurrent(d,None,NULL);glXDestroyWindow(d,glx[0]);snapshot("drawable-destroyed-window-alive");
    glx[0]=glXCreateWindow(d,configs[0],children[0],NULL);glXMakeCurrent(d,glx[0],ctx);draw(glx[0],0);snapshot("drawable-recreated");
    XReparentWindow(d,children[0],owners[1],10,50);XSync(d,False);snapshot("reparent-before-next-swap");
    draw(glx[0],0);snapshot("reparent-after-swap");
    glXMakeCurrent(d,None,NULL);glXDestroyWindow(d,glx[0]);glx[0]=glXCreateWindow(d,configs[0],children[0],NULL);glXMakeCurrent(d,glx[0],ctx);draw(glx[0],0);snapshot("reparent-drawable-recreated");
    glXMakeCurrent(d,None,NULL);XDestroyWindow(d,children[0]);snapshot("window-destroy-before-next-swap");glXDestroyWindow(d,glx[0]);
    glXMakeCurrent(d,glx[1],ctx);draw(glx[1],1);snapshot("other-child-next-swap");
    glXMakeCurrent(d,None,NULL);glXDestroyWindow(d,glx[1]);XDestroyWindow(d,children[1]);snapshot("both-windows-destroyed");
    FILE *maps=fopen("/proc/self/maps","r");char mapline[2048];if(!maps)return 9;
    while(fgets(mapline,sizeof(mapline),maps))if(strstr(mapline,"/"))printf("MAP %s",mapline);
    fclose(maps);
    glXDestroyContext(d,ctx);XDestroyWindow(d,owners[0]);XDestroyWindow(d,owners[1]);XFree(v);XFree(configs);XCloseDisplay(d);printf("FINAL xerrors=%u frames=%u\n",errors,frames);return 0;
}
