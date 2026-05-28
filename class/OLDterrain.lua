local gltf = require 'importer.formats.gltf'

local Terrain = {}
Terrain.__index = Terrain

local CHUNK_SIZE = 256
local TEX_SIZE   = 257
local PAD        = 10
local HSCALE     = 64

local chunkMesh = gltf.load{ path = 'assets/chunk.glb'    }[1].mesh
local lodMesh   = gltf.load{ path = 'assets/chunkLod.glb' }[1].mesh

local terrainShader = LG.newShader('shader/terrain.glsl')

local instanceFormat = {
    { 'iWorldXZ', 'float', 2 },
    { 'iAtlasUV', 'float', 2 },
}

local function loadHeightImage(path, pad)
    local src = love.image.newImageData(path)
    local sw, sh = src:getDimensions()
    local data = love.image.newImageData(sw + 2*pad, sh + 2*pad)
    data:paste(src, pad, pad, 0, 0, sw, sh)
    -- репликация краёв в паддинг
    for p = 1, pad do
        data:paste(src, pad - p, pad,         0,      0,      1,  sh)  -- left col
        data:paste(src, pad + sw + p - 1, pad, sw - 1, 0,      1,  sh)  -- right col
        data:paste(src, pad, pad - p,         0,      0,      sw, 1)   -- top row
        data:paste(src, pad, pad + sh + p - 1, 0,     sh - 1, sw, 1)   -- bottom row
    end
    local img = LG.newImage(data)
    img:setFilter('linear')
    img:setWrap('clamp')
    return img
end

function Terrain:new(opts)
    opts = opts or {}
    local self = setmetatable({}, Terrain)
    self.chunks = {}
    self.lodDist = opts.lodDist or 512
    return self
end

function Terrain:import(dir)
    local files = {}
    for _, name in ipairs(LF.getDirectoryItems(dir)) do
        local X, Y = name:match('^(%d+)_(%d+)%.png$')
        if X then
            files[#files+1] = { name = name, X = tonumber(X), Y = tonumber(Y) }
        end
    end
    -- атлас: укладываем плитки в сетку cols × rows, размер выбираем под количество
    local n = #files
    local cols = math.ceil(math.sqrt(n))
    local rows = math.ceil(n / cols)
    local tilePx = TEX_SIZE + PAD * 2
    local atlasW = cols * tilePx
    local atlasH = rows * tilePx
    local atlas = LG.newCanvas(atlasW, atlasH, { format = 'r8' })
    atlas:setFilter('linear', 'linear')
    atlas:setWrap('clamp')

    LG.setCanvas(atlas)
    LG.clear(0, 0, 0, 1)
    for i, f in ipairs(files) do
        local slot = i - 1
        local col = slot % cols
        local row = math.floor(slot / cols)
        local px = col * tilePx + PAD
        local py = row * tilePx + PAD
        local img = loadHeightImage(dir .. '/' .. f.name, PAD)
        LG.draw(img, px - PAD, py - PAD)
        self.chunks[#self.chunks+1] = {
            cx = f.X, cy = f.Y,
            wx = f.X * CHUNK_SIZE, wz = f.Y * CHUNK_SIZE,
            atlasU = px / atlasW,
            atlasV = py / atlasH,
        }
    end
    LG.setCanvas()

    self.atlas = atlas
    self.atlasW = atlasW
    self.atlasH = atlasH
    self.tileUvW = TEX_SIZE / atlasW
    self.tileUvH = TEX_SIZE / atlasH

    -- per-instance меши (буфер сразу под все чанки)
    
    self.nearInstances = LG.newMesh(instanceFormat, #self.chunks, nil, 'dynamic')
    self.farInstances  = LG.newMesh(instanceFormat, #self.chunks, nil, 'dynamic')
    chunkMesh:attachAttribute('iWorldXZ', self.nearInstances, 'perinstance')
    chunkMesh:attachAttribute('iAtlasUV', self.nearInstances, 'perinstance')
    lodMesh:attachAttribute('iWorldXZ', self.farInstances, 'perinstance')
    lodMesh:attachAttribute('iAtlasUV', self.farInstances, 'perinstance')

end

function Terrain:draw(camera)
    local cx, cz = camera.pos.x, camera.pos.z
    local d2 = self.lodDist * self.lodDist
    local nearList, farList = {}, {}
    for _, c in ipairs(self.chunks) do
        local dx, dz = c.wx - cx, c.wz - cz
        if dx*dx + dz*dz < d2 then
            nearList[#nearList+1] = { c.wx, c.wz, c.atlasU, c.atlasV }
        else
            farList[#farList+1] = { c.wx, c.wz, c.atlasU, c.atlasV }
        end
    end

    self.nearCount = #nearList
    self.farCount  = #farList
    if self.nearCount > 0 then self.nearInstances:setVertices(nearList) end
    if self.farCount > 0  then self.farInstances:setVertices(farList)   end


    local shader = terrainShader
    LG.setShader(shader)
    shader:send('viewproj', camera:viewproj())
    shader:send('hScale', HSCALE)
    shader:send('heightmap', self.atlas)
    shader:send('atlasTexelSize', { 1/self.atlasW, 1/self.atlasH })
    shader:send('tileUvSize', { self.tileUvW, self.tileUvH })
    shader:send('cellSize', CHUNK_SIZE / (TEX_SIZE - 1))

    if self.nearCount > 0 then LG.drawInstanced(chunkMesh, self.nearCount) end
    if self.farCount  > 0 then LG.drawInstanced(lodMesh,   self.farCount)  end

    LG.setShader()
end

return Terrain
