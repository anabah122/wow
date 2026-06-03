// Коллектор выходных артефактов конвертера. Вместо записи на диск writer'ы кладут
// результат сюда (имя→байты), а C-API отдаёт буферы Python для записи.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace wc {

struct Artifact {
    std::string name;            // относит. имя, напр. "<stem>.gltf" или "<stem>/terrain.json"
    std::vector<uint8_t> data;
};

// текущий результат (конвертер однопоточный со стороны Python)
std::vector<Artifact>& artifacts();
void clearArtifacts();

// добавить артефакт; path приходит как "<outDir>/<stem><suffix>", outDir="" в либе —
// ведущие '/' срезаются, остаётся чистое относит. имя.
void writeFile(const std::string& path, const void* data, size_t n);

} // namespace wc
