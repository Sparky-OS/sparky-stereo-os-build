/* SPDX-License-Identifier: MIT */
/* SPDX-FileCopyrightText: 2026 Daniel Campos Ramos */
#include <gst/video/video.h>
#include <spa/param/video/format-utils.h>
#include "gstpipewireformat.h"
#include <stdio.h>
int main(int argc,char **argv) {
 gst_init(&argc,&argv);GEnumClass *modes=g_type_class_ref(GST_TYPE_VIDEO_MULTIVIEW_MODE);
 unsigned total=0,failures=0;
 const unsigned flags[]={0,1,2,4,8,16,1<<14,1<<15,0xc01f};
 for(unsigned i=0;i<modes->n_values;i++) {
  int mode=modes->values[i].value;if(mode<0)continue;
  for(unsigned j=0;j<G_N_ELEMENTS(flags);j++) {
   const char *name=gst_video_multiview_mode_to_caps_string(mode);
   GstCaps *caps=gst_caps_new_simple("video/x-raw","format",G_TYPE_STRING,"RGBA","width",G_TYPE_INT,320,"height",G_TYPE_INT,120,"framerate",GST_TYPE_FRACTION,30,1,"views",G_TYPE_INT,2,"multiview-mode",G_TYPE_STRING,name,"multiview-flags",GST_TYPE_VIDEO_MULTIVIEW_FLAGSET,flags[j],G_MAXUINT,NULL);
   GPtrArray *pods=gst_caps_to_format_all(caps);struct spa_video_info_raw f={0};
   gboolean good=pods->len==1 && spa_format_video_raw_parse(pods->pdata[0],&f)>=0 && f.multiview_mode==mode && f.multiview_flags==flags[j] && f.views==2;
   GstCaps *back=pods->len?gst_caps_from_format(pods->pdata[0]):NULL;
   if(back) {
    const GstStructure *s=gst_caps_get_structure(back,0);const GValue *v=gst_structure_get_value(s,"multiview-flags");int views=0;
    good=good && g_strcmp0(gst_structure_get_string(s,"multiview-mode"),name)==0 && v && gst_value_get_flagset_flags(v)==flags[j] && gst_value_get_flagset_mask(v)==G_MAXUINT && gst_structure_get_int(s,"views",&views) && views==2;
    gst_caps_unref(back);
   } else good=FALSE;
   printf("mode=%s flags=%u expected=0 found=%u\n",name,flags[j],!good);total++;failures+=!good;
   g_ptr_array_set_free_func(pods,g_free);g_ptr_array_unref(pods);gst_caps_unref(caps);
  }
 }
 printf("rows=%u failures=%u\n",total,failures);g_type_class_unref(modes);return failures?1:0;
}
