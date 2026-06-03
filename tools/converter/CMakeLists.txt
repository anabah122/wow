cmake_minimum_required(VERSION 3.15)
project(wowconv LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Корень wowee (берём лоадеры БЕЗ изменений — всегда актуальный код)
set(WOWEE "${CMAKE_CURRENT_SOURCE_DIR}/../../wowee")

if(WIN32)
    add_compile_definitions(NOMINMAX _CRT_SECURE_NO_WARNINGS)
endif()
add_compile_definitions(GLM_ENABLE_EXPERIMENTAL GLM_FORCE_DEPTH_ZERO_TO_ONE)

# Конвертер — DLL (C-API для ctypes из Python). Только парс+сериализация в память.
# Открытие MPQ, обход и запись на диск делает Python (convert.py).
add_library(wowconv SHARED
    capi.cpp
    sink.cpp
    gltf_writer.cpp
    writers2.cpp
    # лоадеры wowee как есть
    ${WOWEE}/src/pipeline/m2_loader.cpp
    ${WOWEE}/src/pipeline/wmo_loader.cpp
    ${WOWEE}/src/pipeline/adt_loader.cpp
    ${WOWEE}/src/pipeline/blp_loader.cpp
    # инфраструктура wowee, нужная лоадерам
    ${WOWEE}/src/core/logger.cpp
)

# выходная dll — рядом с convert.py (tools/converter/)
set_target_properties(wowconv PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY         "${CMAKE_CURRENT_SOURCE_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_CURRENT_SOURCE_DIR}")

target_include_directories(wowconv PRIVATE
    ${WOWEE}/include
    ${WOWEE}/extern              # nlohmann/json.hpp
    ${CMAKE_CURRENT_SOURCE_DIR}/extern/glm
)
