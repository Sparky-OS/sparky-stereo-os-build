/* Test aid: logs, with times, the ConfigureNotify (real or synthetic) and the property changes of every top-level window under the root. */
#include <xcb/xcb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1000.0+t.tv_nsec/1e6; }
int main(void){
  xcb_connection_t *c = xcb_connect(NULL,NULL); if (xcb_connection_has_error(c)) return 1;
  xcb_screen_t *s = xcb_setup_roots_iterator(xcb_get_setup(c)).data;
  uint32_t m = XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY;
  xcb_change_window_attributes(c, s->root, XCB_CW_EVENT_MASK, &m);
  xcb_flush(c);
  double t0 = now();
  xcb_generic_event_t *e;
  while ((e = xcb_wait_for_event(c))) {
    int type = e->response_type & 0x7f, sent = e->response_type & 0x80;
    if (type == XCB_CREATE_NOTIFY) {
      xcb_create_notify_event_t *ev = (void*)e;
      uint32_t mm = XCB_EVENT_MASK_STRUCTURE_NOTIFY | XCB_EVENT_MASK_PROPERTY_CHANGE;
      xcb_change_window_attributes(c, ev->window, XCB_CW_EVENT_MASK, &mm); xcb_flush(c);
      printf("%8.0f create   win=0x%x %dx%d\n", now()-t0, ev->window, ev->width, ev->height);
    } else if (type == XCB_CONFIGURE_NOTIFY) {
      xcb_configure_notify_event_t *ev = (void*)e;
      if (ev->width > 100) printf("%8.0f configure win=0x%x event=0x%x %s %dx%d at %d,%d\n", now()-t0, ev->window, ev->event, sent?"SYNTHETIC":"real    ", ev->width, ev->height, ev->x, ev->y);
    } else if (type == XCB_MAP_NOTIFY) {
      xcb_map_notify_event_t *ev = (void*)e;
      char nm[200]="", cl[200]="";
      xcb_get_property_reply_t *r1 = xcb_get_property_reply(c, xcb_get_property(c,0,ev->window,XCB_ATOM_WM_NAME,XCB_ATOM_ANY,0,50),NULL);
      if (r1) { int l=xcb_get_property_value_length(r1); if(l>199)l=199; memcpy(nm,xcb_get_property_value(r1),l); nm[l]=0; free(r1);}
      xcb_get_property_reply_t *r2 = xcb_get_property_reply(c, xcb_get_property(c,0,ev->window,XCB_ATOM_WM_CLASS,XCB_ATOM_ANY,0,50),NULL);
      if (r2) { int l=xcb_get_property_value_length(r2); if(l>199)l=199; memcpy(cl,xcb_get_property_value(r2),l); cl[l]=0; for(int i=0;i<l;i++) if(!cl[i]) cl[i]=' '; free(r2);}
      printf("%8.0f map      win=0x%x name=\"%s\" class=\"%s\"\n", now()-t0, ev->window, nm, cl);
      
    } else if (type == XCB_UNMAP_NOTIFY) {
      xcb_unmap_notify_event_t *ev = (void*)e; printf("%8.0f unmap    win=0x%x\n", now()-t0, ev->window);
    } else if (type == XCB_PROPERTY_NOTIFY) {
      xcb_property_notify_event_t *ev = (void*)e;
      xcb_get_atom_name_reply_t *r = xcb_get_atom_name_reply(c, xcb_get_atom_name(c, ev->atom), NULL);
      if (r) { char n[128]; int l = xcb_get_atom_name_name_length(r); if (l>127) l=127; memcpy(n, xcb_get_atom_name_name(r), l); n[l]=0;
        if (strstr(n,"STEREO") || strstr(n,"NORMAL_HINTS") || strstr(n,"STATE") || strstr(n,"NET_WM_SIZE")) printf("%8.0f property  win=0x%x %s\n", now()-t0, ev->window, n); free(r); }
    }
    fflush(stdout); free(e);
  }
  return 0;
}
