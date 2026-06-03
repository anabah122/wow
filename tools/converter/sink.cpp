#include "sink.hpp"

namespace wc {

static std::vector<Artifact> g_artifacts;

std::vector<Artifact>& artifacts() { return g_artifacts; }
void clearArtifacts() { g_artifacts.clear(); }

void writeFile(const std::string& path, const void* data, size_t n) {
    std::string name = path;
    size_t i = 0;
    while (i < name.size() && (name[i] == '/' || name[i] == '\\')) ++i;   // срез ведущих слешей
    name = name.substr(i);
    const uint8_t* b = static_cast<const uint8_t*>(data);
    g_artifacts.push_back({ std::move(name), std::vector<uint8_t>(b, b + n) });
}

} // namespace wc
