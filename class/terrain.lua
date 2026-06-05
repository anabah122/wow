-- террейн из нескольких ADT. НЕ читает диск — всё грузит terrainImporter.
-- держит готовые ADT-ресурсы + GO-инстансы doodad/wmo, рисует чанки и пассы моделей.
local generateChunkMesh = require 'class.util.chunkMesh'
local terrainImporter   = require 'class.terrainImporter'
local Go                = require 'class.go'
local Batcher           = require 'class.batcher'

local terrainShader = LG.newShader('shader/wow.glsl')
local doodadShader  = LG.newShader('shader/doodad.glsl')

local Terrain = {}
Terrain.__index = Terrain

function Terrain:new()
    local self = setmetatable({}, Terrain)
    self.chunkMesh  = generateChunkMesh()
    self.adts       = {}                -- готовые ресурсы ADT от импортера
    self.gos        = {}
    self.batcher    = Batcher:new()     -- doodad'ы
    self.wmoBatcher = Batcher:new()     -- WMO («глубже»)
    self.doodadInst  = {}               -- glb -> { {x,y,z,qx,qy,qz,qw,scale}, ... }
    self.doodadIsWmo = {}
    return self
end

function Terrain:loadAdt(dir)
    local a = terrainImporter.import(dir)
    self.adts[#self.adts+1] = a

    for _, d in ipairs(a.doodads) do
        local list = self.doodadInst[d.glb]
        if not list then list = {}; self.doodadInst[d.glb] = list end
        list[#list+1] = d.instance
        self.doodadIsWmo[d.glb] = d.isWmo
    end
end

-- загрузить ВСЕ тайлы из папки карты (подпапки <map>_<tx>_<ty>).
-- центр блока (средние tx,ty) возвращаем для постановки камеры.
function Terrain:loadDir(dir)
    local minx, miny, maxx, maxy
    for _, name in ipairs(LF.getDirectoryItems(dir)) do
        local tx, ty = name:match('_(%d+)_(%d+)$')
        if tx and LF.getInfo(dir .. '/' .. name .. '/terrain.json') then
            tx, ty = tonumber(tx), tonumber(ty)
            self:loadAdt(dir .. '/' .. name)
            minx = math.min(minx or tx, tx); maxx = math.max(maxx or tx, tx)
            miny = math.min(miny or ty, ty); maxy = math.max(maxy or ty, ty)
        end
    end
    if not minx then return nil end
    return (minx + maxx) / 2, (miny + maxy) / 2
end

-- создать GO из собранных инстансов (после всех loadAdt)
function Terrain:build()
    local made, miss = 0, 0
    for glb, instances in pairs(self.doodadInst) do
        if LF.getInfo(glb) then
            local batcher = self.doodadIsWmo[glb] and self.wmoBatcher or self.batcher
            self.gos[#self.gos+1] = Go:new{ path = glb, batcher = batcher, instances = instances }
            made = made + 1
        else
            miss = miss + 1
        end
    end
    print(string.format('terrain: %d adts, doodads %d ok / %d missing glb', #self.adts, made, miss))
end

function Terrain:update(dt) end

function Terrain:draw(camera)
    local vp = camera:viewproj()

    -- террейн: каждый ADT своими текстурами
    LG.setShader(terrainShader)
    LG.setMeshCullMode('back')
    LG.setBlendMode('replace')
    LG.setDepthMode('lequal', true)
    terrainShader:send('viewproj', vp)
    terrainShader:send('texTile', 8)
    for _, a in ipairs(self.adts) do
        terrainShader:send('hGrid',  { a.grid, a.grid })          -- размеры атласов per-ADT (из конвертера)
        terrainShader:send('mGrid',  { a.maskTile, a.maskTile })
        terrainShader:send('mChunk', a.maskChunk)
        terrainShader:send('heightmap', a.heightTex)
        terrainShader:send('maskmap', a.maskTex)
        terrainShader:send('diffuse', a.diffuse)
        for _, attr in ipairs{ 'iWorldXZ','iHeightUV','iMaskUV','iLayers','iNLayers' } do
            self.chunkMesh:attachAttribute(attr, a.instanceMesh, 'perinstance')
        end
        LG.drawInstanced(self.chunkMesh, a.count)
    end

    -- doodad-пассы (см. doc/render.md)
    LG.setShader(doodadShader)
    doodadShader:send('viewproj', vp)
    local function drawBatcher(batcher)
        LG.setBlendMode('replace'); LG.setDepthMode('lequal', true)
        doodadShader:send('uAlphaMode', 0.0); batcher:drawPass(1)   -- opaque: альфа игнор
        LG.setBlendMode('alpha')
        doodadShader:send('uAlphaMode', 1.0); batcher:drawPass(2)   -- cutout: discard
        LG.setDepthMode('lequal', false)                            -- transparent
        doodadShader:send('uAlphaMode', 2.0)
        LG.setBlendMode('alpha'); batcher:drawPass(4)
        LG.setBlendMode('add');   batcher:drawPass(5)
    end
    drawBatcher(self.wmoBatcher)
    drawBatcher(self.batcher)

    LG.setMeshCullMode('back')
    LG.setBlendMode('alpha')
    LG.setDepthMode()
    LG.setShader()
end

return Terrain
