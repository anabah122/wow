-- рендер редактируемого блока через shader/terrain.glsl.
-- инстансы чанков статичны (только позиция); материалы — через карту индексов блока.
local generateChunkMesh = require 'class.util.chunkMesh'
local dims              = require 'class.util.dims'

local CHUNK = dims.CHUNK
local BLOCK = dims.BLOCK
local SIZE  = dims.SIZE

local shader = LG.newShader('shader/terrain.glsl')

-- per-instance только позиция чанка; индексы материалов читаются из карты в шейдере
local INSTANCE_FMT = {
    { 'iChunkXZ', 'float', 2 },
}

local render = {}
render.__index = render

function render:new()
    local self = setmetatable({}, render)
    self.mesh = generateChunkMesh()
    self.inst = LG.newMesh(INSTANCE_FMT, BLOCK * BLOCK, nil, 'static')
    for cy = 0, BLOCK - 1 do
        for cx = 0, BLOCK - 1 do
            self.inst:setVertex(cy * BLOCK + cx + 1, { cx * CHUNK, cy * CHUNK })
        end
    end
    self.mesh:attachAttribute('iChunkXZ', self.inst, 'perinstance')
    return self
end

function render:draw(camera, block, tiles, matCount)
    LG.setShader(shader)
    LG.setMeshCullMode('none')
    LG.setBlendMode('replace')
    LG.setDepthMode('lequal', true)
    shader:send('viewproj', camera:viewproj())
    shader:send('uBlockOrigin', { -SIZE / 2, -SIZE / 2 })   -- блок вокруг нуля
    shader:send('uMatCount', matCount or 1)
    shader:send('heightmap', block.heightTex)
    shader:send('materialmap', block.materialTex)
    shader:send('matIndexMap', block.matIndexTex)
    if tiles then shader:send('tiles', tiles) end
    LG.drawInstanced(self.mesh, BLOCK * BLOCK)
    LG.setShader(); LG.setBlendMode('alpha'); LG.setDepthMode()
end

-- мировую точку в экранные пиксели; nil если за камерой
local function project(vp, x, y, z)
    local px, py, pz, pw = vp:mulVec4(x, y, z, 1)
    if pw <= 0 then return nil end
    return (px / pw * 0.5 + 0.5) * LG.getWidth(), (-py / pw * 0.5 + 0.5) * LG.getHeight()
end

-- круг кисти НА террейне: кольцо точек по рельефу вокруг (wx,wz), проекция в экран, линия
function render:drawBrush(camera, block, wx, wz, radius)
    local vp = camera:viewproj()
    local pts, SEG = {}, 48
    for i = 0, SEG do
        local a = i / SEG * math.pi * 2
        local x = wx + math.cos(a) * radius
        local z = wz + math.sin(a) * radius
        local sx, sy = project(vp, x, block:hAtWorld(x, z), z)
        if not sx then return end
        pts[#pts+1] = sx; pts[#pts+1] = sy
    end
    LG.setColor(1, 0.9, 0.2)
    LG.line(pts)
    LG.setColor(1, 1, 1)
end

return render
