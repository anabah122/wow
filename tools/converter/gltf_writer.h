#pragma once
#include <string>
#include "pipeline/m2_loader.hpp"
#include "pipeline/adt_loader.hpp"
#include "pipeline/wmo_loader.hpp"
#include "pipeline/blp_loader.hpp"

// Все писатели: в биты идёт ТОЛЬКО геометрия/пиксели, остальное в JSON.
// Координаты WoW (Z-up) -> glTF (Y-up): (x, z, -y).
// relPath — WoW-путь файла относительно src-корня (для относительных uri текстур).

// uri текстуры от папки модели до текстуры (оба WoW-пути), .png
std::string texUri(const std::string& texWowPath, const std::string& modelWowPath);

// M2 -> <stem>.gltf + .bin + .m2.json
void writeM2Gltf(const wowee::pipeline::M2Model& model,
                 const std::string& outDir, const std::string& stem, const std::string& relPath);

// WMO -> <stem>.gltf + .bin (геометрия групп) + .wmo.json (материалы/порталы/doodad-сеты/etc.)
void writeWMOGltf(const wowee::pipeline::WMOModel& model,
                  const std::string& outDir, const std::string& stem, const std::string& relPath);

// ADT -> <stem>.adt.json (террейн: чанки/высоты/слои/альфа/doodad+wmo placements/вода)
void writeADTJson(const wowee::pipeline::ADTTerrain& adt,
                  const std::string& outDir, const std::string& stem, bool bigAlpha);

// BLP -> <stem>.png (RGBA8)
void writeBLPPng(const wowee::pipeline::BLPImage& img,
                 const std::string& outDir, const std::string& stem);
