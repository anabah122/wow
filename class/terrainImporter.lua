-- импорт одного ADT-атласа (выход wowconv.exe) -> готовые к рендеру GPU-ресурсы.
-- ВСЁ чтение с диска (height.r32, mask.png, bind.png, terrain.json, tileset png) — здесь.
-- import(dir, tx, ty) -> {
--   heightTex, maskTex, diffuse,         -- текстуры для wow.glsl
--   instanceMesh, count,                 -- 16x16 чанков-инстансов
--   doodads = { {names, placements, isWmo}, ... }   -- сырьё моделей для terrain:build
-- }
local importer = require 'importer.importer'
local ffi      = require 'ffi'

-- placement -> движковый инстанс { x,y,z, qx,qy,qz,qw, scale }.
-- конвертер уже отдал готовые position и quat в движковой системе — просто читаем.
local function placeWorld(p)
    return {
        p.position[1], p.position[2], p.position[3],
        p.quat[1], p.quat[2], p.quat[3], p.quat[4],
        (p.scale or 1024) / 1024,
    }
end

local OUTER  = 9
local HSTEP  = OUTER - 1          -- 8 текселей высоты на чанк
local UNIT   = 33.33333 / 8       -- ярдов на тексель
local TILE   = 533.33333
local GRID   = 129                -- атлас высот ADT
local MASK   = 64                 -- маск-окно чанка (нативный MCAL 64x64)
local MTILE  = 1024               -- маск-атлас ADT
local CHUNKS = 16

local INSTANCE_FMT = {
    { 'iWorldXZ',  'float', 2 },
    { 'iHeightUV', 'float', 2 },
    { 'iMaskUV',   'float', 2 },
    { 'iLayers',   'float', 4 },
    { 'iNLayers',  'float', 1 },
}

local M = {}

-- height.r32 -> R32F текстура (абсолютная Z в ярдах)
local function loadHeight(dir)
    local raw = assert(LF.read(dir .. '/height.r32'), 'no height.r32')
    local img = love.image.newImageData(GRID, GRID, 'r32f')
    ffi.copy(img:getFFIPointer(), raw, GRID * GRID * 4)
    local tex = LG.newImage(img)
    tex:setFilter('linear', 'linear'); tex:setWrap('clamp')
    return tex
end

local function loadMask(dir)
    local tex = LG.newImage(dir .. '/mask.png')
    tex:setFilter('linear', 'linear'); tex:setWrap('clamp')
    return tex
end

-- terrain.json.tiles уже содержит зеркальный путь с .png -> префикс converted/
local function tilePng(tile)
    return ('assets/converted/' .. tile:gsub('\\', '/')):lower()
end

-- diffuse ArrayImage из tiles[] (по слою на тайлсет).
-- ArrayImage требует одинаковый размер слоёв; тайлы WoW бывают разного (напр. 8x8
-- заглушки) -> приводим каждый к 256x256.
local TILE_SIZE = 256
local function loadDiffuse(tiles)
    local slices = {}
    for i, blp in ipairs(tiles) do
        local src = love.image.newImageData(tilePng(blp))
        if src:getWidth() == TILE_SIZE and src:getHeight() == TILE_SIZE then
            slices[i] = src
        else
            local dst = love.image.newImageData(TILE_SIZE, TILE_SIZE, 'rgba8')
            dst:paste(src, 0, 0, 0, 0, math.min(src:getWidth(), TILE_SIZE), math.min(src:getHeight(), TILE_SIZE))
            slices[i] = dst
        end
    end
    local img = LG.newArrayImage(slices, { mipmaps = true })
    img:setFilter('linear', 'linear'); img:setWrap('repeat', 'repeat')
    return img
end

-- bind.png: R/G/B/A = textureId слоёв 1..4 (нормализ id/tilesCount). textureId=0 валиден
-- (нулевой тайл), поэтому число слоёв НЕ угадываем — берём из json.nLayers.
-- -> iLayers (1-based индексы diffuse) + iNLayers
local function chunkLayers(bind, cx, cy, tilesCount, nL)
    local r, g, b, a = bind:getPixel(cx, cy)
    return math.round(r * tilesCount) + 1, math.round(g * tilesCount) + 1,
           math.round(b * tilesCount) + 1, math.round(a * tilesCount) + 1, nL
end

-- 16x16 чанков -> instanceMesh. nLayers[] из json (реальное число слоёв на чанк, индекс cy*16+cx)
-- maskChunk — размер окна маски на чанк в текселях (из конвертера, не хардкод)
local function buildInstances(bind, tilesCount, nLayers, maskChunk, tx, ty)
    local mesh = LG.newMesh(INSTANCE_FMT, CHUNKS * CHUNKS, nil, 'static')
    local n = 0
    for cy = 0, CHUNKS - 1 do
        for cx = 0, CHUNKS - 1 do
            local L1, L2, L3, L4, nL = chunkLayers(bind, cx, cy, tilesCount, nLayers[cy * CHUNKS + cx + 1])
            n = n + 1
            mesh:setVertex(n, {
                tx * TILE + cx * HSTEP * UNIT, ty * TILE + cy * HSTEP * UNIT,
                cx * HSTEP,                    cy * HSTEP,         -- база вершины в текселях высот (0..128)
                cx * maskChunk,                cy * maskChunk,     -- база окна маски в текселях
                L1, L2, L3, L4, nL,
            })
        end
    end
    return mesh, n
end

-- names/placements тайла -> список { glb, isWmo, instance } с готовой движковой трансформой
local function modelGlb(name)
    return ('assets/converted/' .. name:gsub('\\', '/')):lower()
end
local function collectDoodads(out, names, placements, isWmo)
    for _, p in ipairs(placements or {}) do
        local name = names[p.nameId + 1]
        if name then
            out[#out+1] = { glb = modelGlb(name), isWmo = isWmo, instance = placeWorld(p) }
        end
    end
end

function M.import(dir)
    local json = require('lib.json').decode(LF.read(dir .. '/terrain.json'))
    local bind = love.image.newImageData(dir .. '/bind.png')
    local mesh, count = buildInstances(bind, json.tilesCount, json.nLayers, json.maskChunk, json.coord[1], json.coord[2])

    local doodads = {}
    collectDoodads(doodads, json.doodadNames, json.doodadPlacements, false)
    collectDoodads(doodads, json.wmoNames,    json.wmoPlacements,    true)

    return {
        heightTex    = loadHeight(dir),
        maskTex      = loadMask(dir),
        diffuse      = loadDiffuse(json.tiles),
        instanceMesh = mesh,
        count        = count,
        doodads      = doodads,
        grid         = json.grid,       -- размеры атласов из конвертера (не хардкод)
        maskTile     = json.maskTile,
        maskChunk    = json.maskChunk,
    }
end

return M
