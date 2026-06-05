-- террейн из блоков чанков. НЕ читает диск — всё грузит terrainImporter.
-- держит готовые ресурсы блоков + GO-инстансы моделей, рисует чанки и модели.
local terrainImporter   = require 'class.terrainImporter'
local dims              = require 'class.util.dims'
local Go                = require 'class.go'
local Batcher           = require 'class.batcher'

local terrainShader = LG.newShader('shader/terrain.glsl')
local modelShader   = LG.newShader('shader/model.glsl')

local BLOCK_SIZE = dims.BLOCK * dims.CHUNK   -- размер блока в ячейках

local Terrain = {}
Terrain.__index = Terrain

function Terrain:new()
    local self = setmetatable({}, Terrain)
    self.blocks    = {}              -- готовые ресурсы блоков
    self.gos       = {}
    self.batcher   = Batcher:new()
    self.modelInst = {}             -- glb -> { {x,y,z,qx,qy,qz,qw,scale}, ... }
    return self
end

-- ox,oy — смещение блока в мире (ячейки)
function Terrain:loadBlock(dir, ox, oy)
    local b = terrainImporter.import(dir)
    b.ox, b.oy = ox or 0, oy or 0
    self.blocks[#self.blocks+1] = b

    for glb, instances in pairs(b.models) do
        local list = self.modelInst[glb]
        if not list then list = {}; self.modelInst[glb] = list end
        for _, inst in ipairs(instances) do list[#list+1] = inst end
    end
end

-- загрузить все блоки из папки карты (подпапки <map>_<tx>_<ty>).
-- центр блока возвращаем для постановки камеры.
function Terrain:loadDir(dir)
    local minx, miny, maxx, maxy
    for _, name in ipairs(LF.getDirectoryItems(dir)) do
        local tx, ty = name:match('_(%d+)_(%d+)$')
        if tx and LF.getInfo(dir .. '/' .. name .. '/chunk.json') then
            tx, ty = tonumber(tx), tonumber(ty)
            self:loadBlock(dir .. '/' .. name, tx * BLOCK_SIZE, ty * BLOCK_SIZE)
            minx = math.min(minx or tx, tx); maxx = math.max(maxx or tx, tx)
            miny = math.min(miny or ty, ty); maxy = math.max(maxy or ty, ty)
        end
    end
    if not minx then return nil end
    return (minx + maxx) / 2, (miny + maxy) / 2
end

-- создать GO из собранных инстансов (после всех loadBlock)
function Terrain:build()
    local made, miss = 0, 0
    for glb, instances in pairs(self.modelInst) do
        if LF.getInfo(glb) then
            self.gos[#self.gos+1] = Go:new{ path = glb, batcher = self.batcher, instances = instances }
            made = made + 1
        else
            miss = miss + 1
        end
    end
    print(string.format('terrain: %d blocks, models %d ok / %d missing', #self.blocks, made, miss))
end

function Terrain:update(dt) end

function Terrain:draw(camera)
    local vp = camera:viewproj()

    LG.setShader(terrainShader)
    LG.setMeshCullMode('back')
    LG.setBlendMode('replace')
    LG.setDepthMode('lequal', true)
    terrainShader:send('viewproj', vp)
    terrainShader:send('uBlockSize', BLOCK_SIZE)
    for _, b in ipairs(self.blocks) do
        terrainShader:send('uBlockOrigin', { b.ox, b.oy })
        terrainShader:send('uHeightTexel', { 1 / b.heightTex:getWidth(), 1 / b.heightTex:getHeight() })
        terrainShader:send('heightmap', b.heightTex)
        terrainShader:send('materialmap', b.materialTex)
        LG.drawInstanced(b.chunkMesh, b.count)
    end

    LG.setShader(modelShader)
    LG.setBlendMode('alpha')
    LG.setDepthMode('lequal', true)
    modelShader:send('viewproj', vp)
    self.batcher:draw()

    LG.setMeshCullMode('back')
    LG.setBlendMode('alpha')
    LG.setDepthMode()
    LG.setShader()
end

return Terrain
