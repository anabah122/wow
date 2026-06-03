#include "gltf_writer.h"
#include "sink.hpp"
#include <nlohmann/json.hpp>
#include <vector>
#include <cstdint>
#include <cstring>
#include <limits>
#include <filesystem>

// uri текстуры: путь от папки модели к текстуре (оба WoW-пути), расширение -> .png.
// gltf.lua резолвит относительно папки .gltf и схлопывает ../, поэтому зеркало структуры
// converted/<wow path> делает ссылки рабочими без ремапа.
std::string texUri(const std::string& texWowPath, const std::string& modelWowPath) {
    namespace fs = std::filesystem;
    std::string t = texWowPath, m = modelWowPath;
    // нижний регистр + '/': пути в M2/WMO (MixedCase) и на диске (relPath, UPPERCASE)
    // расходятся регистром -> fs::relative не видит общий префикс и теряет сегменты.
    for (auto& c:t) { if (c=='\\') c='/'; else c=(char)tolower((unsigned char)c); }
    for (auto& c:m) { if (c=='\\') c='/'; else c=(char)tolower((unsigned char)c); }
    auto dot = t.rfind('.'); if (dot!=std::string::npos) t = t.substr(0,dot); t += ".png";
    fs::path rel = fs::relative(fs::path(t), fs::path(m).parent_path());
    std::string s = rel.generic_string();
    return s.empty() ? t : s;
}

using json = nlohmann::json;
using namespace wowee::pipeline;

namespace {

// glTF константы
constexpr int FLOAT = 5126, U16 = 5123, U8 = 5121;
constexpr int ARRAY_BUF = 34962, ELEM_BUF = 34963;

// аккумулятор бинарного буфера
struct Bin {
    std::vector<uint8_t> data;
    void append(const void* p, size_t n) {
        const uint8_t* b = static_cast<const uint8_t*>(p);
        data.insert(data.end(), b, b + n);
    }
    void pad4() { while (data.size() % 4) data.push_back(0); }
    size_t size() const { return data.size(); }
};

using wc::writeFile;

// сериализация M2AnimationTrack -> json (см. doc/m2_format.md: Track)
json trackJson(const M2AnimationTrack& t) {
    json j;
    j["interpolationType"] = t.interpolationType;
    j["globalSequence"] = t.globalSequence;
    json seqs = json::array();
    for (const auto& s : t.sequences) {
        json sj;
        sj["timestamps"] = s.timestamps;
        if (!s.vec3Values.empty()) {
            json a = json::array();
            for (auto& v : s.vec3Values) a.push_back({ v.x, v.y, v.z });
            sj["vec3"] = a;
        }
        if (!s.quatValues.empty()) {
            json a = json::array();
            for (auto& q : s.quatValues) a.push_back({ q.x, q.y, q.z, q.w });
            sj["quat"] = a;
        }
        if (!s.floatValues.empty()) sj["float"] = s.floatValues;
        seqs.push_back(sj);
    }
    j["sequences"] = seqs;
    return j;
}

json fblockJson(const M2FBlock& fb) {
    json j;
    j["timestamps"] = fb.timestamps;
    if (!fb.vec3Values.empty()) {
        json a = json::array();
        for (auto& v : fb.vec3Values) a.push_back({ v.x, v.y, v.z });
        j["vec3"] = a;
    }
    if (!fb.floatValues.empty()) j["float"] = fb.floatValues;
    return j;
}

} // namespace

void writeM2Gltf(const M2Model& model, const std::string& outDir, const std::string& stem,
                 const std::string& relPath) {
    const std::string base = outDir + "/" + stem;

    // ── бинарный буфер геометрии (Z-up -> Y-up: x, z, -y) ──
    Bin bin;
    json views = json::array();
    json accs  = json::array();

    auto addView = [&](size_t byteLen, int target) -> int {
        json v = { {"buffer", 0}, {"byteOffset", bin.size() - byteLen}, {"byteLength", byteLen} };
        if (target) v["target"] = target;
        views.push_back(v);
        return static_cast<int>(views.size()) - 1;
    };
    auto addAccessor = [&](int view, int ctype, int count, const char* type, json extra = json()) -> int {
        json a = { {"bufferView", view}, {"componentType", ctype}, {"count", count}, {"type", type} };
        if (!extra.is_null()) for (auto it = extra.begin(); it != extra.end(); ++it) a[it.key()] = it.value();
        accs.push_back(a);
        return static_cast<int>(accs.size()) - 1;
    };

    const int nV = static_cast<int>(model.vertices.size());

    // POSITION
    {
        float mn[3] = { 1e30f, 1e30f, 1e30f }, mx[3] = { -1e30f, -1e30f, -1e30f };
        size_t start = bin.size();
        for (const auto& v : model.vertices) {
            float p[3] = { v.position.x, v.position.z, -v.position.y };  // Z-up -> Y-up
            bin.append(p, 12);
            for (int k = 0; k < 3; ++k) { if (p[k] < mn[k]) mn[k] = p[k]; if (p[k] > mx[k]) mx[k] = p[k]; }
        }
        int view = addView(bin.size() - start, ARRAY_BUF); bin.pad4();
        addAccessor(view, FLOAT, nV, "VEC3",
            { {"min", {mn[0], mn[1], mn[2]}}, {"max", {mx[0], mx[1], mx[2]}} });
    }
    int aPos = 0;
    // NORMAL
    int aNrm;
    { size_t s = bin.size();
      for (const auto& v : model.vertices) { float n[3] = { v.normal.x, v.normal.z, -v.normal.y }; bin.append(n, 12); }
      int view = addView(bin.size() - s, ARRAY_BUF); bin.pad4(); aNrm = addAccessor(view, FLOAT, nV, "VEC3"); }
    // TEXCOORD_0
    int aUv0;
    { size_t s = bin.size();
      for (const auto& v : model.vertices) { float u[2] = { v.texCoords[0].x, v.texCoords[0].y }; bin.append(u, 8); }
      int view = addView(bin.size() - s, ARRAY_BUF); bin.pad4(); aUv0 = addAccessor(view, FLOAT, nV, "VEC2"); }
    // TEXCOORD_1
    int aUv1;
    { size_t s = bin.size();
      for (const auto& v : model.vertices) { float u[2] = { v.texCoords[1].x, v.texCoords[1].y }; bin.append(u, 8); }
      int view = addView(bin.size() - s, ARRAY_BUF); bin.pad4(); aUv1 = addAccessor(view, FLOAT, nV, "VEC2"); }
    // JOINTS_0 (u8 vec4)
    int aJnt;
    { size_t s = bin.size();
      for (const auto& v : model.vertices) bin.append(v.boneIndices, 4);
      int view = addView(bin.size() - s, ARRAY_BUF); bin.pad4(); aJnt = addAccessor(view, U8, nV, "VEC4"); }
    // WEIGHTS_0 (f32 vec4, 0..255 -> 0..1)
    int aWgt;
    { size_t s = bin.size();
      for (const auto& v : model.vertices) {
          float w[4] = { v.boneWeights[0]/255.f, v.boneWeights[1]/255.f, v.boneWeights[2]/255.f, v.boneWeights[3]/255.f };
          bin.append(w, 16); }
      int view = addView(bin.size() - s, ARRAY_BUF); bin.pad4(); aWgt = addAccessor(view, FLOAT, nV, "VEC4"); }

    // индексы (общий буфер, primitive на батч через byteOffset)
    int idxView;
    { size_t s = bin.size();
      bin.append(model.indices.data(), model.indices.size() * 2);
      idxView = addView(bin.size() - s, ELEM_BUF); bin.pad4(); }

    // ── материалы glTF + текстуры + primitives (по батчам) ──
    json gMats = json::array(), gTex = json::array(), gImg = json::array();
    json prims = json::array();
    std::vector<std::string> imgUris;
    auto texFor = [&](const std::string& filename) -> int {
        if (filename.empty()) return -1;
        std::string png = texUri(filename, relPath);
        for (size_t i = 0; i < imgUris.size(); ++i) if (imgUris[i] == png) return static_cast<int>(i);
        gImg.push_back({ {"uri", png} });
        gTex.push_back({ {"source", static_cast<int>(gImg.size()) - 1} });
        imgUris.push_back(png);
        return static_cast<int>(gTex.size()) - 1;
    };

    for (const auto& b : model.batches) {
        if (b.indexCount == 0) continue;
        int aIdx = addAccessor(idxView, U16, b.indexCount, "SCALAR", { {"byteOffset", b.indexStart * 2} });

        // текстура: batch.textureIndex -> textureLookup -> textures
        int texGltf = -1;
        if (b.textureIndex < model.textureLookup.size()) {
            uint16_t slot = model.textureLookup[b.textureIndex];
            if (slot < model.textures.size()) texGltf = texFor(model.textures[slot].filename);
        }
        uint16_t flags = 0, blend = 0;
        if (b.materialIndex < model.materials.size()) {
            flags = model.materials[b.materialIndex].flags;
            blend = model.materials[b.materialIndex].blendMode;
        }
        json mat;
        mat["pbrMetallicRoughness"] = { {"metallicFactor", 0}, {"roughnessFactor", 1} };
        mat["doubleSided"] = (flags & 0x04) != 0;            // TwoSided
        mat["extras"] = { {"blendMode", blend}, {"flags", flags} };
        if (texGltf >= 0)
            mat["pbrMetallicRoughness"]["baseColorTexture"] = { {"index", texGltf} };
        gMats.push_back(mat);

        prims.push_back({
            {"attributes", {
                {"POSITION", aPos}, {"NORMAL", aNrm},
                {"TEXCOORD_0", aUv0}, {"TEXCOORD_1", aUv1},
                {"JOINTS_0", aJnt}, {"WEIGHTS_0", aWgt}
            }},
            {"indices", aIdx},
            {"material", static_cast<int>(gMats.size()) - 1}
        });
    }

    // ── записать .bin ──
    writeFile(base + ".bin", bin.data.data(), bin.data.size());

    // ── .gltf ──
    json gltf;
    gltf["asset"] = { {"version", "2.0"}, {"generator", "wowconv"} };
    gltf["scene"] = 0;
    gltf["scenes"] = json::array({ { {"nodes", {0}} } });
    gltf["nodes"] = json::array({ { {"mesh", 0}, {"name", model.name} } });
    gltf["meshes"] = json::array({ { {"primitives", prims}, {"name", model.name} } });
    gltf["accessors"] = accs;
    gltf["bufferViews"] = views;
    gltf["buffers"] = json::array({ { {"uri", stem + ".bin"}, {"byteLength", bin.data.size()} } });
    gltf["materials"] = gMats;
    gltf["textures"] = gTex;
    gltf["images"] = gImg;
    { std::string s = gltf.dump(1, '\t'); writeFile(base + ".gltf", s.data(), s.size()); }

    // ── .m2.json: вся M2-специфика (геометрия в .bin не дублируется) ──
    json m;
    m["name"] = model.name; m["version"] = model.version; m["globalFlags"] = model.globalFlags;
    m["boundMin"] = { model.boundMin.x, model.boundMin.y, model.boundMin.z };
    m["boundMax"] = { model.boundMax.x, model.boundMax.y, model.boundMax.z };
    m["boundRadius"] = model.boundRadius;

    json bones = json::array();
    for (const auto& b : model.bones) {
        bones.push_back({
            {"keyBoneId", b.keyBoneId}, {"flags", b.flags},
            {"parentBone", b.parentBone}, {"submeshId", b.submeshId},
            {"pivot", { b.pivot.x, b.pivot.y, b.pivot.z }},
            {"translation", trackJson(b.translation)},
            {"rotation", trackJson(b.rotation)},
            {"scale", trackJson(b.scale)}
        });
    }
    m["bones"] = bones;
    m["boneLookupTable"] = model.boneLookupTable;

    json seqs = json::array();
    for (const auto& s : model.sequences) {
        seqs.push_back({
            {"id", s.id}, {"variationIndex", s.variationIndex}, {"duration", s.duration},
            {"movingSpeed", s.movingSpeed}, {"flags", s.flags}, {"frequency", s.frequency},
            {"replayMin", s.replayMin}, {"replayMax", s.replayMax}, {"blendTime", s.blendTime},
            {"boundMin", { s.boundMin.x, s.boundMin.y, s.boundMin.z }},
            {"boundMax", { s.boundMax.x, s.boundMax.y, s.boundMax.z }},
            {"boundRadius", s.boundRadius},
            {"nextAnimation", s.nextAnimation}, {"aliasNext", s.aliasNext}
        });
    }
    m["sequences"] = seqs;
    m["globalSequenceDurations"] = model.globalSequenceDurations;

    json mats = json::array();
    for (const auto& mm : model.materials) mats.push_back({ {"flags", mm.flags}, {"blendMode", mm.blendMode} });
    m["materials"] = mats;

    json texs = json::array();
    for (const auto& t : model.textures) texs.push_back({ {"type", t.type}, {"flags", t.flags}, {"filename", t.filename} });
    m["textures"] = texs;
    m["textureLookup"] = model.textureLookup;

    json batches = json::array();
    for (const auto& b : model.batches) {
        batches.push_back({
            {"flags", b.flags}, {"priorityPlane", b.priorityPlane}, {"shader", b.shader},
            {"skinSectionIndex", b.skinSectionIndex}, {"colorIndex", b.colorIndex},
            {"materialIndex", b.materialIndex}, {"materialLayer", b.materialLayer},
            {"textureCount", b.textureCount}, {"textureIndex", b.textureIndex},
            {"textureUnit", b.textureUnit}, {"transparencyIndex", b.transparencyIndex},
            {"textureAnimIndex", b.textureAnimIndex},
            {"indexStart", b.indexStart}, {"indexCount", b.indexCount},
            {"vertexStart", b.vertexStart}, {"vertexCount", b.vertexCount},
            {"submeshId", b.submeshId}, {"submeshLevel", b.submeshLevel}
        });
    }
    m["batches"] = batches;

    json tts = json::array();
    for (const auto& t : model.textureTransforms)
        tts.push_back({ {"translation", trackJson(t.translation)}, {"rotation", trackJson(t.rotation)}, {"scale", trackJson(t.scale)} });
    m["textureTransforms"] = tts;
    m["textureTransformLookup"] = model.textureTransformLookup;
    m["textureWeights"] = model.textureWeights;
    m["colorAlphas"] = model.colorAlphas;

    json atts = json::array();
    for (const auto& a : model.attachments)
        atts.push_back({ {"id", a.id}, {"bone", a.bone}, {"position", { a.position.x, a.position.y, a.position.z }} });
    m["attachments"] = atts;
    m["attachmentLookup"] = model.attachmentLookup;

    json parts = json::array();
    for (const auto& e : model.particleEmitters) {
        parts.push_back({
            {"particleId", e.particleId}, {"flags", e.flags},
            {"position", { e.position.x, e.position.y, e.position.z }},
            {"bone", e.bone}, {"texture", e.texture},
            {"blendingType", e.blendingType}, {"emitterType", e.emitterType},
            {"textureTileRotation", e.textureTileRotation},
            {"textureRows", e.textureRows}, {"textureCols", e.textureCols},
            {"emissionSpeed", trackJson(e.emissionSpeed)}, {"speedVariation", trackJson(e.speedVariation)},
            {"verticalRange", trackJson(e.verticalRange)}, {"horizontalRange", trackJson(e.horizontalRange)},
            {"gravity", trackJson(e.gravity)}, {"lifespan", trackJson(e.lifespan)},
            {"emissionRate", trackJson(e.emissionRate)}, {"emissionAreaLength", trackJson(e.emissionAreaLength)},
            {"emissionAreaWidth", trackJson(e.emissionAreaWidth)}, {"deceleration", trackJson(e.deceleration)},
            {"particleColor", fblockJson(e.particleColor)}, {"particleAlpha", fblockJson(e.particleAlpha)},
            {"particleScale", fblockJson(e.particleScale)}
        });
    }
    m["particleEmitters"] = parts;

    json ribs = json::array();
    for (const auto& r : model.ribbonEmitters) {
        ribs.push_back({
            {"ribbonId", r.ribbonId}, {"bone", r.bone},
            {"position", { r.position.x, r.position.y, r.position.z }},
            {"textureIndex", r.textureIndex}, {"materialIndex", r.materialIndex},
            {"colorTrack", trackJson(r.colorTrack)}, {"alphaTrack", trackJson(r.alphaTrack)},
            {"heightAboveTrack", trackJson(r.heightAboveTrack)}, {"heightBelowTrack", trackJson(r.heightBelowTrack)},
            {"visibilityTrack", trackJson(r.visibilityTrack)},
            {"edgesPerSecond", r.edgesPerSecond}, {"edgeLifetime", r.edgeLifetime}, {"gravity", r.gravity},
            {"textureRows", r.textureRows}, {"textureCols", r.textureCols}
        });
    }
    m["ribbonEmitters"] = ribs;

    json cv = json::array();
    for (auto& v : model.collisionVertices) cv.push_back({ v.x, v.y, v.z });
    m["collisionVertices"] = cv;
    m["collisionIndices"] = model.collisionIndices;
    json cn = json::array();
    for (auto& n : model.collisionNormals) cn.push_back({ n.x, n.y, n.z, n.w });
    m["collisionNormals"] = cn;

    { std::string s = m.dump(1, '\t'); writeFile(base + ".m2.json", s.data(), s.size()); }
}
