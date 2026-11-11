/* SPDX-License-Identifier: MIT */
/* A held first frame: raw eyes, actual Present events and compositor capture. */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xcomposite.h>
#include <xcb/xcb.h>
#include <xcb/present.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static Display *d;
static xcb_connection_t *events;
static xcb_special_event_t *queue;
static int stereo;
static unsigned errors;
static unsigned long long ns(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (unsigned long long)t.tv_sec*1000000000+t.tv_nsec;}
static void save(const char *phase,const char *kind,int eye,const void *data,size_t size)
{
 char path[256];snprintf(path,sizeof(path),"%s-%s-%d.raw",phase,kind,eye);
 FILE *f=fopen(path,"wx");if(!f||fwrite(data,1,size,f)!=size)exit(8);fclose(f);
}
static void read_eye(const char *phase,const char *kind,int eye,int w,int h,int stamp)
{
 unsigned char *p=calloc(w*h,3);unsigned bad=0;
 glReadBuffer((!strcmp(kind,"back")?GL_BACK_LEFT:GL_FRONT_LEFT)+(eye?1:0));
 glReadPixels(0,0,w,h,GL_RGB,GL_UNSIGNED_BYTE,p);
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){
  unsigned char *v=p+3*(y*w+x);
  if(v[0]!=(x&255)||v[1]!=(y&255)||v[2]!=(stamp|(eye<<7)))bad++;
 }
 unsigned ge=glGetError();errors+=bad+(ge!=0);
 printf("RAW phase=%s buffer=%s eye=%d size=%dx%d errors=%u gl_error=%u\n",phase,kind,eye,w,h,bad,ge);
 save(phase,kind,eye,p,w*h*3);free(p);
}
static void frame(Window child,GLXWindow glx,const char *phase,int w,int h,int stamp)
{
 xcb_generic_event_t *event;while((event=xcb_poll_for_special_event(events,queue)))free(event);
 glViewport(0,0,w,h);glMatrixMode(GL_PROJECTION);glLoadIdentity();glOrtho(0,w,0,h,-1,1);glMatrixMode(GL_MODELVIEW);glLoadIdentity();
 glDisable(GL_DITHER);glDisable(GL_BLEND);glPixelStorei(GL_PACK_ALIGNMENT,1);glPixelStorei(GL_UNPACK_ALIGNMENT,1);
 for(int eye=0;eye<(stereo?2:1);eye++){
  unsigned char *p=calloc(w*h,3);
  for(int y=0;y<h;y++)for(int x=0;x<w;x++){unsigned char *v=p+3*(y*w+x);v[0]=x;v[1]=y;v[2]=stamp|(eye<<7);}
  glDrawBuffer(eye?GL_BACK_RIGHT:GL_BACK_LEFT);glRasterPos2i(0,0);glDrawPixels(w,h,GL_RGB,GL_UNSIGNED_BYTE,p);free(p);
  read_eye(phase,"back",eye,w,h,stamp);
 }
 printf("SWAP_BEGIN phase=%s ns=%llu\n",phase,ns());fflush(stdout);
 glXSwapBuffers(d,glx);glFinish();XSync(d,False);
 printf("SWAP_RETURN phase=%s ns=%llu\n",phase,ns());
 int completed=0;
 for(int i=0;i<500;i++){
  event=xcb_poll_for_special_event(events,queue);
  if(!event){usleep(10000);continue;}
  xcb_present_generic_event_t *generic=(void*)event;
  if(generic->evtype==XCB_PRESENT_COMPLETE_NOTIFY){
   xcb_present_complete_notify_event_t *e=(void*)event;
   printf("PRESENT phase=%s serial=%u kind=%u mode=%u ust=%llu msc=%llu\n",phase,e->serial,e->kind,e->mode,(unsigned long long)e->ust,(unsigned long long)e->msc);
   completed=e->kind==XCB_PRESENT_COMPLETE_KIND_PIXMAP;
  }
  free(event);if(completed)break;
 }
 printf("COMPLETED phase=%s pixmap=%d requested=%dx%d stamp=%d\n",phase,completed,w,h,stamp);
 if(!completed)errors++;
 if (!getenv("PAIR_NO_FRONT_READBACK"))
  for(int eye=0;eye<(stereo?2:1);eye++)read_eye(phase,"front",eye,w,h,stamp);
 else printf("FRONT_READBACK_DISABLED phase=%s\n",phase);
 XWindowAttributes a;XGetWindowAttributes(d,child,&a);
 Atom type;int format;unsigned long n,left;unsigned char *prop=NULL;
 XGetWindowProperty(d,child,XInternAtom(d,"_KDE_NET_WM_STEREO_CONTENT",False),0,1,False,XA_CARDINAL,&type,&format,&n,&left,&prop);
 printf("WINDOW phase=%s xid=%lu size=%dx%d declaration=%lu\n",phase,child,a.width,a.height,n?*(unsigned long*)prop:0);if(prop)XFree(prop);
 printf("CAPTURE %s\n",phase);fflush(stdout);if(getchar()!='\n')exit(10);
 int declared=n!=0;
 Pixmap pix=declared?XCompositeNameWindowPixmap(d,child):child;Window root;int x,y;unsigned pw,ph,border,depth;
 XGetGeometry(d,pix,&root,&x,&y,&pw,&ph,&border,&depth);
 XImage *im=XGetImage(d,pix,0,0,pw,ph,AllPlanes,ZPixmap);if(!im)exit(9);
 printf("XIMAGE_SOURCE phase=%s kind=%s drawable=%lu\n",phase,declared?"named-pixmap":"window",pix);
 printf("XIMAGE phase=%s size=%ux%u stride=%d bpp=%d order=%d masks=%lx,%lx,%lx\n",phase,pw,ph,im->bytes_per_line,im->bits_per_pixel,im->byte_order,im->red_mask,im->green_mask,im->blue_mask);
 save(phase,"pixmap",0,im->data,im->bytes_per_line*ph);XDestroyImage(im);if(declared)XFreePixmap(d,pix);
}
int main(int argc,char **argv)
{
 stereo=argc>1&&!strcmp(argv[1],"stereo");d=XOpenDisplay(NULL);if(!d)return 1;
 int n;int attrs[]={GLX_X_RENDERABLE,True,GLX_DRAWABLE_TYPE,GLX_WINDOW_BIT,GLX_RENDER_TYPE,GLX_RGBA_BIT,GLX_DOUBLEBUFFER,True,GLX_STEREO,stereo,GLX_RED_SIZE,8,GLX_GREEN_SIZE,8,GLX_BLUE_SIZE,8,None};
 GLXFBConfig *cfg=glXChooseFBConfig(d,DefaultScreen(d),attrs,&n);if(!cfg||!n)return 77;
 XVisualInfo *v=glXGetVisualFromFBConfig(d,cfg[0]);if(!v)return 2;
 Window owner=XCreateSimpleWindow(d,DefaultRootWindow(d),20,20,400,300,0,0,0x204060);
 XSizeHints hints={0};hints.flags=USPosition;hints.x=hints.y=20;XSetWMNormalHints(d,owner,&hints);XStoreName(d,owner,"Kopper held first frame");
 XSetWindowAttributes a={0};a.colormap=XCreateColormap(d,DefaultRootWindow(d),v->visual,AllocNone);
 Window child=XCreateWindow(d,owner,10,50,240,140,0,v->depth,InputOutput,v->visual,CWColormap,&a);
 XMapWindow(d,owner);XMapWindow(d,child);XSync(d,False);usleep(300000);
 events=xcb_connect(NULL,NULL);uint32_t eid=xcb_generate_id(events);
 queue=xcb_register_for_special_xge(events,&xcb_present_id,eid,NULL);
 xcb_present_select_input(events,eid,child,XCB_PRESENT_EVENT_MASK_COMPLETE_NOTIFY);xcb_flush(events);free(xcb_get_input_focus_reply(events,xcb_get_input_focus(events),NULL));
 GLXWindow glx=glXCreateWindow(d,cfg[0],child,NULL);GLXContext ctx=glXCreateNewContext(d,cfg[0],GLX_RGBA_TYPE,NULL,True);if(!ctx||!glXMakeCurrent(d,glx,ctx))return 3;
 printf("IDS owner=%lu child=%lu glx=%lu\nRENDERER %s\n",owner,child,glx,glGetString(GL_RENDERER));
 frame(child,glx,"initial",240,140,1);
 XResizeWindow(d,child,200,120);XSync(d,False);
 frame(child,glx,"first-resize",200,120,2);frame(child,glx,"second-resize",200,120,3);
 FILE *maps=fopen("/proc/self/maps","r");char line[2048];while(fgets(line,sizeof(line),maps))if(strstr(line,"/"))printf("MAP %s",line);fclose(maps);
 glXMakeCurrent(d,None,NULL);glXDestroyContext(d,ctx);glXDestroyWindow(d,glx);XDestroyWindow(d,owner);XFree(v);XFree(cfg);XCloseDisplay(d);xcb_disconnect(events);
 printf("FINAL raw_errors=%u\n",errors);return errors?4:0;
}
