-- импорт одного блока чанков -> готовые к рендеру GPU-ресурсы.
-- всё чтение с диска (chunk.json, height.png, material.png) — здесь.
-- import(dir) -> {
--   heightTex, materialTex,            -- маски блока (linear)
--   chunkMesh, count,                 -- готовый к drawInstanced меш BLOCKxBLOCK чанков
--   models = { glb -> { {x,y,z,qx,qy,qz,qw,scale}, ... } }  -- сырьё для terrain:build
-- }
local generateChunkMesh = require 'class.util.chunkMesh'
local dims              = require 'class.util.dims'
local json              = require 'lib.json'

local CHUNK = dims.CHUNK    -- ячеек на сторону чанка
local BLOCK = dims.BLOCK    -- чанков на сторону блока

-- per-chunk: смещение чанка в блоке (ячейки) + 4 индекса материала
local INSTANCE_FMT = {
    { 'iChunkXZ', 'float', 2 },
    { 'iMatInd',  'float', 4 },
}

local M = {}

local function loadMask(path)
    local tex = LG.newImage(path)
    tex:setFilter('linear', 'linear'); tex:setWrap('clamp')
    return tex
end

-- BLOCKxBLOCK чанков -> готовый chunkMesh с привязанным per-instance буфером (matInd + смещение)
local function buildChunkMesh(chunks)
    local inst = LG.newMesh(INSTANCE_FMT, BLOCK * BLOCK, nil, 'static')
    for cy = 0, BLOCK - 1 do
        for cx = 0, BLOCK - 1 do
            local i = cy * BLOCK + cx + 1
            local m = chunks[i].matInd
            inst:setVertex(i, {
                cx * CHUNK, cy * CHUNK,
                m[1], m[2], m[3], m[4],
            })
        end
    end

    local mesh = generateChunkMesh()
    for _, attr in ipairs{ 'iChunkXZ', 'iMatInd' } do
        mesh:attachAttribute(attr, inst, 'perinstance')
    end
    return mesh, BLOCK * BLOCK
end

-- плоский список инстансов -> { glb -> {инстансы} } для инстансинга
local function collectModels(instances)
    local out = {}
    for _, p in ipairs(instances) do
        local list = out[p.model]
        if not list then list = {}; out[p.model] = list end
        local q = p.quat
        list[#list+1] = { p.x, p.y, p.z, q[1], q[2], q[3], q[4], p.scale or 1 }
    end
    return out
end

function M.import(dir)
    local data = json.decode(LF.read(dir .. '/chunk.json'))
    local mesh, count = buildChunkMesh(data.chunks)
    return {
        heightTex   = loadMask(dir .. '/height.png'),
        materialTex = loadMask(dir .. '/material.png'),
        chunkMesh   = mesh,
        count       = count,
        models      = collectModels(data.instances),
    }
end

return M
