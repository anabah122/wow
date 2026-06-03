// C-API конвертера (ctypes из Python). Только парс (лоадеры wowee) + сериализация
// (наши writers) в буферы памяти. Никакого I/O и MPQ — это делает Python.
//
// Протокол: wc_convert_* очищает результат и наполняет его артефактами; затем
// Python забирает их через wc_artifact_*. Конвертер однопоточный со стороны Python.
#include "gltf_writer.h"
#include "sink.hpp"
#include "pipeline/m2_loader.hpp"
#include "pipeline/wmo_loader.hpp"
#include "pipeline/adt_loader.hpp"
#include "pipeline/blp_loader.hpp"
#include <cstdint>
#include <string>
#include <vector>

using namespace wowee::pipeline;

#if defined(_WIN32)
#define WC_API extern "C" __declspec(dllexport)
#else
#define WC_API extern "C"
#endif

static std::vector<uint8_t> toVec(const uint8_t* p, size_t n) {
    return (p && n) ? std::vector<uint8_t>(p, p + n) : std::vector<uint8_t>();
}

// stem из WoW-пути: basename без расширения, lowercase.
static std::string stemOf(const std::string& path) {
    size_t a = path.find_last_of("/\\");
    size_t b = path.find_last_of('.');
    size_t start = (a == std::string::npos) ? 0 : a + 1;
    size_t len = (b == std::string::npos || b < start) ? std::string::npos : b - start;
    std::string s = path.substr(start, len);
    for (auto& c : s) c = (char)tolower((unsigned char)c);
    return s;
}

// data — .m2, skin — соответствующий 00.skin (может быть пуст), relPath — WoW-путь .m2.
WC_API int wc_convert_m2(const uint8_t* data, size_t n,
                         const uint8_t* skin, size_t sn, const char* relPath) {
    wc::clearArtifacts();
    auto buf = toVec(data, n);
    if (buf.empty()) return 1;
    M2Model model = M2Loader::load(buf);
    auto skinBuf = toVec(skin, sn);
    if (!skinBuf.empty()) M2Loader::loadSkin(skinBuf, model);
    if (!model.isValid()) return 2;
    writeM2Gltf(model, "", stemOf(relPath), relPath);
    return 0;
}

// data — root .wmo, groups[] — группы _000.wmo.. в порядке индекса, relPath — WoW-путь root.
WC_API int wc_convert_wmo(const uint8_t* data, size_t n,
                          const uint8_t* const* groups, const size_t* groupSizes,
                          size_t nGroups, const char* relPath) {
    wc::clearArtifacts();
    auto buf = toVec(data, n);
    if (buf.empty()) return 1;
    WMOModel model = WMOLoader::load(buf);
    if (!model.isValid()) return 2;
    model.groups.resize(model.nGroups);
    for (uint32_t i = 0; i < model.nGroups && i < nGroups; ++i) {
        auto gd = toVec(groups[i], groupSizes[i]);
        if (!gd.empty()) WMOLoader::loadGroup(gd, model, i);
    }
    writeWMOGltf(model, "", stemOf(relPath), relPath);
    return 0;
}

// data — .adt, stem — basename без расширения (артефакты лягут в подпапку <stem>/).
// bigAlpha — WDT MPHD флаг (0x4|0x80): несжатая альфа 8-bit/4096 вместо 4-bit/2048.
WC_API int wc_convert_adt(const uint8_t* data, size_t n, const char* stem, int bigAlpha) {
    wc::clearArtifacts();
    auto buf = toVec(data, n);
    if (buf.empty()) return 1;
    ADTTerrain adt = ADTLoader::load(buf);
    if (!adt.loaded) return 2;
    std::string s = stem ? stem : "";
    for (auto& c : s) c = (char)tolower((unsigned char)c);
    writeADTJson(adt, "", s, bigAlpha != 0);
    return 0;
}

// data — .blp, stem — basename без расширения (артефакт = <stem>.png).
WC_API int wc_convert_blp(const uint8_t* data, size_t n, const char* stem) {
    wc::clearArtifacts();
    auto buf = toVec(data, n);
    if (buf.empty()) return 1;
    BLPImage img = BLPLoader::load(buf);
    if (!img.isValid()) return 2;
    std::string s = stem ? stem : "";
    for (auto& c : s) c = (char)tolower((unsigned char)c);
    writeBLPPng(img, "", s);
    return 0;
}

// доступ к результату последнего wc_convert_*
WC_API size_t      wc_artifact_count()        { return wc::artifacts().size(); }
WC_API const char* wc_artifact_name(size_t i) { return i < wc::artifacts().size() ? wc::artifacts()[i].name.c_str() : nullptr; }
WC_API size_t      wc_artifact_size(size_t i) { return i < wc::artifacts().size() ? wc::artifacts()[i].data.size() : 0; }
WC_API const uint8_t* wc_artifact_data(size_t i) { return i < wc::artifacts().size() ? wc::artifacts()[i].data.data() : nullptr; }
WC_API void        wc_free()                  { wc::clearArtifacts(); }
