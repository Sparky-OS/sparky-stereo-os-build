// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#include <gst/video/video.h>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QByteArray>
#include <dlfcn.h>
struct Input {QByteArray first,second;quint64 ordinal=0;bool temporal=false;bool separated=false;int width=0,height=0;};
extern "C" GstElement *gst_device_create_element(GstDevice *device,const gchar *name) {
    const auto folder=qEnvironmentVariable("KAM61_MATRIX_INPUT");
    if(folder.isEmpty())return reinterpret_cast<GstElement *(*)(GstDevice *,const gchar *)>(dlsym(RTLD_NEXT,"gst_device_create_element"))(device,name);
    QFile spec(folder+"/spec.json");if(!spec.open(QIODevice::ReadOnly))return nullptr;
    auto json=QJsonDocument::fromJson(spec.readAll()).object();
    auto *data=new Input;
    data->width=json["width"].toInt();data->height=json["height"].toInt();
    data->temporal=json["temporal"].toBool();data->separated=json["separated"].toBool();
    QFile first(folder+"/input.raw");first.open(QIODevice::ReadOnly);data->first=first.readAll();
    QFile second(folder+"/second.raw");if(second.open(QIODevice::ReadOnly))data->second=second.readAll();
    auto *source=gst_element_factory_make("appsrc",name);
    auto *caps=gst_caps_new_simple("video/x-raw","format",G_TYPE_STRING,"RGBA","width",G_TYPE_INT,data->width,"height",G_TYPE_INT,data->height,"framerate",GST_TYPE_FRACTION,30,1,nullptr);
    if(data->separated)gst_caps_set_simple(caps,"multiview-mode",G_TYPE_STRING,"separated","views",G_TYPE_INT,2,"multiview-flags",GST_TYPE_VIDEO_MULTIVIEW_FLAGSET,json["rightFirst"].toBool()?GST_VIDEO_MULTIVIEW_FLAGS_RIGHT_VIEW_FIRST:GST_VIDEO_MULTIVIEW_FLAGS_NONE,GST_FLAG_SET_MASK_EXACT,nullptr);
    g_object_set(source,"caps",caps,"is-live",TRUE,"format",GST_FORMAT_TIME,"max-buffers",2,nullptr);gst_caps_unref(caps);
    GstAppSrcCallbacks cb{};
    cb.need_data=[](GstAppSrc *source,guint,gpointer opaque){
        auto *data=static_cast<Input *>(opaque);
        g_usleep(33333);
        const auto &pixels=data->temporal && data->ordinal%2?data->second:data->first;
        const auto size=pixels.size()+(data->separated?data->second.size():0);
        auto *buffer=gst_buffer_new_allocate(nullptr,size,nullptr);gst_buffer_fill(buffer,0,pixels.constData(),pixels.size());
        if(data->separated){
            gst_buffer_fill(buffer,pixels.size(),data->second.constData(),data->second.size());
            for(int id=0;id<2;++id){gsize offsets[GST_VIDEO_MAX_PLANES]={gsize(id*pixels.size())};gint strides[GST_VIDEO_MAX_PLANES]={data->width*4};auto *meta=gst_buffer_add_video_meta_full(buffer,GST_VIDEO_FRAME_FLAG_NONE,GST_VIDEO_FORMAT_RGBA,data->width,data->height,1,offsets,strides);meta->id=id;}
        }
        GST_BUFFER_PTS(buffer)=data->ordinal*GST_SECOND/30;GST_BUFFER_DURATION(buffer)=GST_SECOND/30;GST_BUFFER_OFFSET(buffer)=data->ordinal++;
        gst_app_src_push_buffer(source,buffer);
    };
    gst_app_src_set_callbacks(GST_APP_SRC(source),&cb,data,[](gpointer data){delete static_cast<Input *>(data);});
    return source;
}
