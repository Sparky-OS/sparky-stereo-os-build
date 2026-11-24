#include <QCoreApplication>
#include <QMimeDatabase>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <KFileMetaData/ExtractorCollection>
#include <KFileMetaData/SimpleExtractionResult>
#include <KFileMetaData/PropertyInfo>
#include <stereo-layer/picture.h>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if(argc!=2) return 2;
    QString path=QString::fromLocal8Bit(argv[1]);
    const auto mime=QMimeDatabase().mimeTypeForFile(path).name();
    KFileMetaData::ExtractorCollection collection;
    KFileMetaData::SimpleExtractionResult result(path,mime,KFileMetaData::ExtractionResult::ExtractMetaData);
    const auto extractors=collection.fetchExtractors(mime);
    for(auto *extractor:extractors) extractor->extract(&result);
    QJsonObject obj{{"mime",mime},{"extractors",extractors.size()}};
    const auto properties=result.properties();
    for(auto it=properties.begin();it!=properties.end();++it)
        obj[KFileMetaData::PropertyInfo(it.key()).name()]=QJsonValue::fromVariant(it.value());
    const auto picture=Stereo::Picture::load(path,{},Stereo::OutputMode::Stereo);
    obj["layerStereo"]=picture.isStereo();
    obj["eyeWidth"]=picture.left.width();obj["eyeHeight"]=picture.left.height();
    bool pass=picture.isStereo()&&picture.left.size()==QSize(640,480)&&picture.right.size()==QSize(640,480)&&!properties.empty();
    pass = pass && obj["stereo3dLayout"].toString() == (path.endsWith(".mpo") ? "multiViewLeftFirst" : "sideBySideLeftFirst");
    obj["pass"]=pass;
    qInfo().noquote()<<QJsonDocument(obj).toJson();
    return pass?0:1;
}
