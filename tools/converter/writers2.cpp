// Писатели WMO / ADT / BLP (M2 — в gltf_writer.cpp).
// В биты идёт только геометрия/пиксели, остальное в JSON. Z-up -> Y-up: (x, z, -y).
#include "gltf_writer.h"
#include "sink.hpp"
#include <nlohmann/json.hpp>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>
#include <vector>
#include <array>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <algorithm>

using json = nlohmann::json;
using namespace wowee::pipeline;

namespace {
constexpr int FLOAT = 5126, U16 = 5123;
constexpr int ARRAY_BUF = 34962, ELEM_BUF = 34963;

// MDDF/MODF rotation (эйлеры в градусах) -> готовый кватернион для движка.
// Геометрия свопнута Z-up->Y-up (x,z,-y); ориентация: Ry(ry-90)*Rz(-rz)*Rx(rx).
// Движок просто берёт готовый {x,y,z,w}, ничего не считает.
inline std::array<double,4> placementQuat(const float rot[3]) {
    const double D2R = 3.14159265358979323846 / 180.0;
    double rx = rot[0]*D2R, ry = rot[1]*D2R, rz = rot[2]*D2R;
    auto axis = [](int a, double ang) -> std::array<double,4> {
        double h = ang*0.5, s = std::sin(h), c = std::cos(h);
        if (a==0) return {s,0,0,c};   // x
        if (a==1) return {0,s,0,c};   // y
        return {0,0,s,c};             // z
    };
    auto mul = [](const std::array<double,4>& a, const std::array<double,4>& b) {
        return std::array<double,4>{
            a[3]*b[0] + a[0]*b[3] + a[1]*b[2] - a[2]*b[1],
            a[3]*b[1] - a[0]*b[2] + a[1]*b[3] + a[2]*b[0],
            a[3]*b[2] + a[0]*b[1] - a[1]*b[0] + a[2]*b[3],
            a[3]*b[3] - a[0]*b[0] - a[1]*b[1] - a[2]*b[2]};
    };
    auto q = mul(mul(axis(1, ry - 3.14159265358979323846/2), axis(2, -rz)), axis(0, rx));
    return q;
}

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

// WoW-путь -> lowercase '/' + замена расширения (ссылки = пути на диске)
std::string pathTo(const std::string& p, const char* ext) {
    std::string s = p;
    for (auto& c:s) { if (c=='\\') c='/'; else c=(char)tolower((unsigned char)c); }
    auto d = s.rfind('.'); if (d!=std::string::npos) s = s.substr(0,d);
    return s + ext;
}
} // namespace

// ───────────────────────────── WMO ─────────────────────────────
// Геометрия групп -> .bin (каждая группа = mesh). Материалы/doodad-сеты/группы -> .wmo.json.
void writeWMOGltf(const WMOModel& model, const std::string& outDir, const std::string& stem,
                  const std::string& relPath) {
    const std::string base = outDir + "/" + stem;
    Bin bin;
    json views = json::array(), accs = json::array(), meshes = json::array(), nodes = json::array();
    json gMats = json::array(), gTex = json::array(), gImg = json::array(), sceneNodes = json::array();

    auto addView = [&](size_t len, int target) -> int {
        json v = { {"buffer",0},{"byteOffset",bin.size()-len},{"byteLength",len} };
        if (target) v["target"] = target;
        views.push_back(v); return (int)views.size()-1;
    };
    auto addAcc = [&](int view,int ct,int count,const char* type, json extra=json()) -> int {
        json a = { {"bufferView",view},{"componentType",ct},{"count",count},{"type",type} };
        if (!extra.is_null()) for (auto it=extra.begin(); it!=extra.end(); ++it) a[it.key()]=it.value();
        accs.push_back(a); return (int)accs.size()-1;
    };

    std::vector<std::string> imgUris;
    auto texFor = [&](const std::string& fn) -> int {
        if (fn.empty()) return -1;
        std::string png = texUri(fn, relPath);
        for (size_t i=0;i<imgUris.size();++i) if (imgUris[i]==png) return (int)i;
        gImg.push_back({{"uri",png}}); gTex.push_back({{"source",(int)gImg.size()-1}});
        imgUris.push_back(png); return (int)gTex.size()-1;
    };
    for (const auto& mt : model.materials) {
        // texture1 — байтовый offset в MOTX, переводим в индекс массива textures
        std::string fn;
        auto it = model.textureOffsetToIndex.find(mt.texture1);
        if (it != model.textureOffsetToIndex.end() && it->second < model.textures.size())
            fn = model.textures[it->second];
        int tex = texFor(fn);
        json mat;
        mat["pbrMetallicRoughness"] = { {"metallicFactor",0},{"roughnessFactor",1} };
        mat["doubleSided"] = (mt.flags & 0x04) != 0;
        mat["extras"] = { {"blendMode",mt.blendMode},{"flags",mt.flags},{"shader",mt.shader} };
        if (tex>=0) mat["pbrMetallicRoughness"]["baseColorTexture"] = {{"index",tex}};
        gMats.push_back(mat);
    }

    for (size_t gi = 0; gi < model.groups.size(); ++gi) {
        const auto& g = model.groups[gi];
        if (g.vertices.empty() || g.indices.empty()) continue;
        const int nv = (int)g.vertices.size();
        int aPos, aNrm, aUv;
        { size_t s=bin.size(); float mn[3]={1e30f,1e30f,1e30f},mx[3]={-1e30f,-1e30f,-1e30f};
          for (auto& v:g.vertices){ float p[3]={v.position.x,v.position.z,-v.position.y}; bin.append(p,12);
            for(int k=0;k<3;++k){if(p[k]<mn[k])mn[k]=p[k];if(p[k]>mx[k])mx[k]=p[k];} }
          int view=addView(bin.size()-s,ARRAY_BUF); bin.pad4();
          aPos=addAcc(view,FLOAT,nv,"VEC3",{{"min",{mn[0],mn[1],mn[2]}},{"max",{mx[0],mx[1],mx[2]}}}); }
        { size_t s=bin.size(); for(auto& v:g.vertices){float n[3]={v.normal.x,v.normal.z,-v.normal.y};bin.append(n,12);}
          int view=addView(bin.size()-s,ARRAY_BUF); bin.pad4(); aNrm=addAcc(view,FLOAT,nv,"VEC3"); }
        { size_t s=bin.size(); for(auto& v:g.vertices){float u[2]={v.texCoord.x,v.texCoord.y};bin.append(u,8);}
          int view=addView(bin.size()-s,ARRAY_BUF); bin.pad4(); aUv=addAcc(view,FLOAT,nv,"VEC2"); }
        int idxView; { size_t s=bin.size(); bin.append(g.indices.data(), g.indices.size()*2);
          idxView=addView(bin.size()-s,ELEM_BUF); bin.pad4(); }

        json prims = json::array();
        for (const auto& b : g.batches) {
            if (b.indexCount==0) continue;
            int aIdx = addAcc(idxView,U16,b.indexCount,"SCALAR",{{"byteOffset",(int)b.startIndex*2}});
            json prim = { {"attributes",{{"POSITION",aPos},{"NORMAL",aNrm},{"TEXCOORD_0",aUv}}},{"indices",aIdx} };
            if (b.materialId < gMats.size()) prim["material"] = b.materialId;
            prims.push_back(prim);
        }
        // name = индекс группы WMO (нужно для мержа групп из разных MPQ)
        std::string gname = std::to_string(gi);
        meshes.push_back({ {"primitives",prims},{"name",gname} });
        nodes.push_back({ {"mesh",(int)meshes.size()-1},{"name",gname} });
        sceneNodes.push_back((int)nodes.size()-1);
    }

    writeFile(base + ".bin", bin.data.data(), bin.data.size());

    json gltf;
    gltf["asset"] = { {"version","2.0"},{"generator","wowconv"} };
    gltf["scene"] = 0;
    gltf["scenes"] = json::array({ { {"nodes",sceneNodes} } });
    gltf["nodes"] = nodes; gltf["meshes"] = meshes; gltf["accessors"] = accs; gltf["bufferViews"] = views;
    gltf["buffers"] = json::array({ { {"uri",stem+".bin"},{"byteLength",bin.data.size()} } });
    gltf["materials"] = gMats; gltf["textures"] = gTex; gltf["images"] = gImg;
    { std::string s=gltf.dump(1,'\t'); writeFile(base+".gltf",s.data(),s.size()); }

    json w;
    w["version"]=model.version; w["nGroups"]=model.nGroups;
    w["ambientColor"]={model.ambientColor.x,model.ambientColor.y,model.ambientColor.z};
    w["boundingBoxMin"]={model.boundingBoxMin.x,model.boundingBoxMin.y,model.boundingBoxMin.z};
    w["boundingBoxMax"]={model.boundingBoxMax.x,model.boundingBoxMax.y,model.boundingBoxMax.z};
    json mats=json::array();
    for(auto& m:model.materials) mats.push_back({{"flags",m.flags},{"shader",m.shader},{"blendMode",m.blendMode},
        {"texture1",m.texture1},{"color1",m.color1},{"texture2",m.texture2},{"texture3",m.texture3}});
    w["materials"]=mats;
    json wtex=json::array();
    for(auto& t:model.textures) wtex.push_back(pathTo(t,".png"));   // ссылки = пути на диске
    w["textures"]=wtex;
    json dd=json::array();
    for(auto& d:model.doodads) dd.push_back({{"nameIndex",d.nameIndex},
        {"position",{d.position.x,d.position.y,d.position.z}},
        {"rotation",{d.rotation.x,d.rotation.y,d.rotation.z,d.rotation.w}},{"scale",d.scale}});
    w["doodads"]=dd;
    json dn=json::object();
    for(auto& kv:model.doodadNames) dn[std::to_string(kv.first)]=pathTo(kv.second,".gltf");  // .mdx/.m2 -> .gltf
    w["doodadNames"]=dn;
    json ds=json::array();
    for(auto& s:model.doodadSets){ size_t nlen=0; while(nlen<20 && s.name[nlen]) ++nlen;
        ds.push_back({{"name",std::string(s.name,nlen)},{"startIndex",s.startIndex},{"count",s.count}}); }
    w["doodadSets"]=ds;
    json grp=json::array();
    for(auto& g:model.groups) grp.push_back({{"flags",g.flags},{"groupId",g.groupId},{"name",g.name},
        {"boundingBoxMin",{g.boundingBoxMin.x,g.boundingBoxMin.y,g.boundingBoxMin.z}},
        {"boundingBoxMax",{g.boundingBoxMax.x,g.boundingBoxMax.y,g.boundingBoxMax.z}},
        {"liquidType",g.liquidType}});
    w["groups"]=grp;
    { std::string s=w.dump(1,'\t'); writeFile(base+".wmo.json",s.data(),s.size()); }
}

// ───────────────────────────── ADT ─────────────────────────────
// Атлас НА КАЖДЫЙ ADT в <outDir>/<stem>/: height.r32 / normal.png / mask.png /
// bind.png / terrain.json. Запекание в C++; MCAL fix: 64-я строка/столбец = повтор 63-й.
namespace {
constexpr int ALPHA = 64;        // размер MCAL слоя (атлас-окно чанка)

// декод одного слоя MCAL -> 64x64 (8-bit 0..255). Алгоритм 1:1 с Noggit (Alphamap.cpp):
//   big_alpha: compressed(0x200) -> RLE 4096; иначе 8-bit 4096.
//   без big_alpha: ВСЕГДА 4-bit 2048 (флаг compressed игнорируется), нормализация v|v<<4.
//   fixAlpha (только 4-bit, флаг "do not fix" снят): 64-я строка/столбец = повтор 63-й.
static void decodeMCAL(const MapChunk& c, size_t layerIdx, bool bigAlpha, bool fixAlpha,
                       std::vector<uint8_t>& out) {
    out.assign(ALPHA*ALPHA, 0);
    const auto& layer = c.layers[layerIdx];
    if (!layer.useAlpha() || layer.offsetMCAL >= c.alphaMap.size()) return;
    size_t offset = layer.offsetMCAL;

    if (layer.compressedAlpha()) {
        // RLE -> 4096
        size_t rp = offset, wp = 0;
        while (wp < 4096 && rp < c.alphaMap.size()) {
            uint8_t cmd = c.alphaMap[rp++]; bool fill = cmd & 0x80; int n = cmd & 0x7F;
            if (n == 0) continue;
            if (fill) { if (rp < c.alphaMap.size()) { uint8_t v = c.alphaMap[rp++];
                for (int i=0;i<n && wp<4096;i++) out[wp++]=v; } }
            else for (int i=0;i<n && wp<4096 && rp<c.alphaMap.size();i++) out[wp++]=c.alphaMap[rp++];
        }
    } else {
        // несжатый -> 8-bit 4096 байт напрямую (подтверждено дампом _dbgB_8bit:
        // на этих картах несжатый слой хранится 8-бит даже при big_alpha=0)
        for (int i=0;i<4096 && offset+(size_t)i<c.alphaMap.size();i++) out[i]=c.alphaMap[offset+i];
    }
}
} // namespace

// атлас НА КАЖДЫЙ ADT в <outDir>/<stem>/ :
//   height.r32 (R32F 129x129) / normal.png (RGB8 129x129) / mask.png (RGBA8 1024x1024)
//   bind.png (RGBA8 16x16) / terrain.json (тайлсеты + placements)
void writeADTJson(const ADTTerrain& adt, const std::string& outDir, const std::string& stem, bool bigAlpha) {
    std::string dir = outDir + "/" + stem;   // подпапка артефактов ADT (питон создаст на диске)
    const int tilesCount = (int)adt.textures.size();

    constexpr int GRID=129, OUTER=9, MCHUNK=64, MTILE=MCHUNK*16;
    auto outerIdx=[](int col,int row){ return row*17 + col; };  // outer-вершина из 145-массива

    std::vector<float>   height(GRID*GRID, 0.0f);
    std::vector<uint8_t> normal(GRID*GRID*3, 0);
    std::vector<uint8_t> mask(MTILE*MTILE*4, 0);
    for (size_t i=3;i<mask.size();i+=4) mask[i]=255;   // A не используется -> непрозрачное превью
    std::vector<uint8_t> bind(16*16*4, 0);
    std::array<int,256> nLayersPerChunk{};   // реальное число слоёв на чанк (cy*16+cx)

    std::vector<uint8_t> a64;
    for (int ci=0; ci<256; ++ci) {
        const auto& c = adt.chunks[ci];
        int cx=c.indexX, cy=c.indexY;
        if (c.heightMap.loaded) {
            for (int row=0; row<OUTER; ++row) for (int col=0; col<OUTER; ++col) {
                int dst=(cy*8+row)*GRID + (cx*8+col), oi=outerIdx(col,row);
                height[dst]=c.position[2] + c.heightMap.heights[oi];   // абсолютная Z
                normal[dst*3+0]=(uint8_t)(c.normals[oi*3+0]+128);
                normal[dst*3+1]=(uint8_t)(c.normals[oi*3+1]+128);
                normal[dst*3+2]=(uint8_t)(c.normals[oi*3+2]+128);
            }
        }
        for (size_t li=1; li<c.layers.size() && li<4; ++li) {   // слои 2..4 -> R/G/B; слой1=база
            decodeMCAL(c, li, bigAlpha, true, a64);
            int ch=(int)li-1;
            for (int my=0; my<MCHUNK; ++my) for (int mx=0; mx<MCHUNK; ++mx)
                mask[((cy*MCHUNK+my)*MTILE + cx*MCHUNK+mx)*4 + ch] = a64[my*ALPHA+mx];
        }
        int bdst=(cy*16+cx)*4;
        for (int li=0; li<4; ++li) {
            uint8_t v=0;
            if (li<(int)c.layers.size() && tilesCount>0)
                v=(uint8_t)(255.0f*(float)c.layers[li].textureId/(float)tilesCount + 0.5f);
            bind[bdst+li]=v;
        }
        nLayersPerChunk[cy*16+cx] = std::min((int)c.layers.size(), 4);  // реальное число слоёв
    }

    auto cb=[](void* ctx,void* d,int n){ auto* v=static_cast<std::vector<uint8_t>*>(ctx);
        const uint8_t* b=static_cast<const uint8_t*>(d); v->insert(v->end(),b,b+n); };
    auto pngFile=[&](const std::string& path,int w,int h,int comp,const uint8_t* px){
        std::vector<uint8_t> png; stbi_write_png_to_func(cb,&png,w,h,comp,px,w*comp);
        writeFile(path,png.data(),png.size()); };
    writeFile(dir+"/height.r32", height.data(), height.size()*4);
    pngFile(dir+"/normal.png", GRID, GRID, 3, normal.data());
    pngFile(dir+"/mask.png", MTILE, MTILE, 4, mask.data());
    pngFile(dir+"/bind.png", 16, 16, 4, bind.data());

    json j;
    j["version"]=adt.version;
    // координаты тайла из имени файла (..._<tx>_<ty>); лоадер их не даёт
    int tx = adt.coord.x, ty = adt.coord.y;
    { auto u = stem.rfind('_'); if (u != std::string::npos && u > 0) {
        auto u2 = stem.rfind('_', u-1);
        if (u2 != std::string::npos) { tx = atoi(stem.c_str()+u2+1); ty = atoi(stem.c_str()+u+1); } } }
    j["coord"]={tx,ty};
    j["grid"]=GRID; j["maskTile"]=MTILE; j["maskChunk"]=MCHUNK; j["tilesCount"]=tilesCount;
    j["nLayers"]=nLayersPerChunk;   // реальное число слоёв на чанк (256, индекс cy*16+cx)

    // пути зеркалят структуру converted/<wow path>: lowercase + расширение (pathTo)
    json tiles=json::array();
    for(auto& t:adt.textures) tiles.push_back(pathTo(t,".png"));
    j["tiles"]=tiles;
    json dn=json::array();
    for(auto& n:adt.doodadNames) dn.push_back(pathTo(n,".gltf"));
    j["doodadNames"]=dn;
    json wn=json::array();
    for(auto& n:adt.wmoNames) wn.push_back(pathTo(n,".gltf"));
    j["wmoNames"]=wn;
    json dp=json::array();
    for(auto& d:adt.doodadPlacements){ auto q=placementQuat(d.rotation);
        dp.push_back({{"nameId",d.nameId},{"uniqueId",d.uniqueId},
        {"position",{d.position[0],d.position[1],d.position[2]}},
        {"quat",{q[0],q[1],q[2],q[3]}},{"scale",d.scale},{"flags",d.flags}}); }
    j["doodadPlacements"]=dp;
    json wp=json::array();
    for(auto& w:adt.wmoPlacements){ auto q=placementQuat(w.rotation);
        wp.push_back({{"nameId",w.nameId},{"uniqueId",w.uniqueId},
        {"position",{w.position[0],w.position[1],w.position[2]}},
        {"quat",{q[0],q[1],q[2],q[3]}},
        {"flags",w.flags},{"doodadSet",w.doodadSet},{"scale",w.scale}}); }
    j["wmoPlacements"]=wp;
    std::string s=j.dump(1,'\t'); writeFile(dir+"/terrain.json", s.data(), s.size());
}

// ───────────────────────────── BLP ─────────────────────────────
void writeBLPPng(const BLPImage& img, const std::string& outDir, const std::string& stem) {
    std::string path = outDir + "/" + stem + ".png";
    std::vector<uint8_t> png;
    auto cb = [](void* ctx, void* d, int n) {
        auto* v = static_cast<std::vector<uint8_t>*>(ctx);
        const uint8_t* b = static_cast<const uint8_t*>(d);
        v->insert(v->end(), b, b + n);
    };
    stbi_write_png_to_func(cb, &png, img.width, img.height, 4, img.data.data(), img.width*4);
    wc::writeFile(path, png.data(), png.size());
}
