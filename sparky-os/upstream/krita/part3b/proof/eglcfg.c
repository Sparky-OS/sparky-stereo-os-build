#define EGL_EGLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
int main(void){
  struct wl_display *wd = wl_display_connect(NULL);
  EGLDisplay d = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, wd, NULL);
  EGLint maj,min; if(!eglInitialize(d,&maj,&min)){printf("init fail\n");return 1;}
  printf("EGL %d.%d vendor %s\n",maj,min,eglQueryString(d,EGL_VENDOR));
  printf("exts: %s\n", eglQueryString(d,EGL_EXTENSIONS));
  EGLint n=0; eglGetConfigs(d,NULL,0,&n); EGLConfig *c=malloc(n*sizeof *c); eglGetConfigs(d,c,n,&n);
  for(int i=0;i<n;i++){ EGLint r,g,b,a,t,st,ct=0,rt; eglGetConfigAttrib(d,c[i],EGL_RED_SIZE,&r);eglGetConfigAttrib(d,c[i],EGL_GREEN_SIZE,&g);eglGetConfigAttrib(d,c[i],EGL_BLUE_SIZE,&b);eglGetConfigAttrib(d,c[i],EGL_ALPHA_SIZE,&a);eglGetConfigAttrib(d,c[i],EGL_SURFACE_TYPE,&st);eglGetConfigAttrib(d,c[i],EGL_RENDERABLE_TYPE,&rt);
    eglGetConfigAttrib(d,c[i],EGL_COLOR_COMPONENT_TYPE_EXT,&ct);
    printf("config %d: %d/%d/%d/%d win=%d render=0x%x float=%d\n",i,r,g,b,a,!!(st&EGL_WINDOW_BIT),rt,ct==EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT);}
  return 0;}
