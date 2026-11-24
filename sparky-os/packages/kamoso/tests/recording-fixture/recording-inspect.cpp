// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <gst/gst.h>
#include <dlfcn.h>
#include <atomic>
#include <QCoreApplication>
#include <QTimer>
#include <QFile>
#include <QSaveFile>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonDocument>
struct PadCount { std::atomic<quint64> buffers{0}, pts{GST_CLOCK_TIME_NONE}; };
static PadCount *countPad(GstPad *pad) {
    auto *count=static_cast<PadCount *>(g_object_get_data(G_OBJECT(pad),"kam61-count"));
    if(!count) {
        count=new PadCount;
        g_object_set_data(G_OBJECT(pad),"kam61-count",count);
        gst_pad_add_probe(pad,GST_PAD_PROBE_TYPE_BUFFER,[](GstPad *,GstPadProbeInfo *info,gpointer data) {
            auto *count=static_cast<PadCount *>(data);
            count->pts.store(GST_BUFFER_PTS(GST_PAD_PROBE_INFO_BUFFER(info)));
            count->buffers.fetch_add(1);
            return GST_PAD_PROBE_OK;
        },count,[](gpointer data){delete static_cast<PadCount *>(data);});
    }
    return count;
}
static std::atomic<GstElement *> camera{};
extern "C" GstElement *gst_element_factory_make(const gchar *factory, const gchar *name) {
    auto real=reinterpret_cast<GstElement *(*)(const gchar *,const gchar *)>(dlsym(RTLD_NEXT,"gst_element_factory_make"));
    auto *element=real(factory,name);
    if(g_str_equal(factory,"camerabin")) camera.store(element);
    return element;
}
// This synthetic camera has no hardware capture timestamps. Give its source
// the pipeline clock, just as a timestamped camera would, in this fixture only.
extern "C" GstElement *gst_device_create_element(GstDevice *device, const gchar *name) {
    auto real=reinterpret_cast<GstElement *(*)(GstDevice *,const gchar *)>(dlsym(RTLD_NEXT,"gst_device_create_element"));
    auto *element=real(device,name);
    if(element && g_object_class_find_property(G_OBJECT_GET_CLASS(element),"do-timestamp"))
        g_object_set(element,"do-timestamp",TRUE,nullptr);
    return element;
}
static void begin() {
    auto *timer=new QTimer(QCoreApplication::instance());
    QObject::connect(timer,&QTimer::timeout,[] {
        auto *element=camera.load();if(!element)return;
        QJsonArray rows;GValue item=G_VALUE_INIT;
        auto *iterator=gst_bin_iterate_recurse(GST_BIN(element));
        while(gst_iterator_next(iterator,&item)==GST_ITERATOR_OK) {
            auto *child=GST_ELEMENT(g_value_get_object(&item));
            auto *factory=gst_element_get_factory(child);
            if(!factory){g_value_reset(&item);continue;}
            const auto kind=QString::fromUtf8(gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory)));
            QJsonObject row{{"name",QString::fromUtf8(GST_ELEMENT_NAME(child))},{"factory",kind}};
            for(const char *prop:{"quality","bitrate","pass","quantizer","tune","speed-preset","rate","channels","current-level-buffers","current-level-time","is-live","do-timestamp"}) {
                auto *spec=g_object_class_find_property(G_OBJECT_GET_CLASS(child),prop);
                if(!spec || !(spec->flags&G_PARAM_READABLE))continue;
                GValue v=G_VALUE_INIT;g_value_init(&v,spec->value_type);g_object_get_property(G_OBJECT(child),prop,&v);
                auto *value=g_strdup_value_contents(&v);row[prop]=QString::fromUtf8(value);g_free(value);g_value_unset(&v);
            }
            GstState current,pending;gst_element_get_state(child,&current,&pending,0);
            row["state"]=QString::fromUtf8(gst_element_state_get_name(current));
            row["pending"]=QString::fromUtf8(gst_element_state_get_name(pending));
            for(const char *padName:{"src","sink"}) {
                auto *pad=gst_element_get_static_pad(child,padName);if(!pad)continue;
                auto *count=countPad(pad);
                row[QString::fromUtf8(padName)+"Buffers"]=static_cast<qint64>(count->buffers.load());
                row[QString::fromUtf8(padName)+"PTS"]=QString::number(count->pts.load());
                auto *caps=gst_pad_get_current_caps(pad);
                if(caps){auto *value=gst_caps_to_string(caps);row[padName]=QString::fromUtf8(value);g_free(value);gst_caps_unref(caps);}gst_object_unref(pad);
            }
            rows.append(row);g_value_reset(&item);
        }
        g_value_unset(&item);gst_iterator_free(iterator);
        QSaveFile file(qEnvironmentVariable("KAM61_INSPECT"));if(file.open(QIODevice::WriteOnly)){file.write(QJsonDocument(rows).toJson());file.commit();}
    });timer->start(1000);
}
Q_COREAPP_STARTUP_FUNCTION(begin)
