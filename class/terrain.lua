-- терраин с высотами из текстуры: меш = плоская сетка с UV, высоты сэмплятся в шейдере
local ffi = require 'ffi'

local terrain = {}
terrain.__index = terrain

local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
}

pcall(ffi.cdef, [[
    typedef struct { float x,y,z, u,v; } TerrainVert;
]])

local templates = {}

-- сетка (w+1)x(h+1) вершин, тайл по миру = [0..w*quadSize], UV = [0..1]
local function getTemplate(w, h, quadSize)
    local key = w .. 'x' .. h .. 'x' .. quadSize
    local t = templates[key]
    if t then return t end

    local W, H = w + 1, h + 1
    local triCount  = w * h * 2
    local vertCount = triCount * 3
    local bytes = ffi.sizeof('TerrainVert') * vertCount
    local bd = love.data.newByteData(bytes)
    local verts = ffi.cast('TerrainVert*', bd:getFFIPointer())

    local invW, invH = 1 / w, 1 / h
    local function emit(i, x, y)
        local v = verts[i]
        v.x = x * quadSize
        v.y = 0
        v.z = y * quadSize
        v.u = x * invW
        v.v = y * invH
    end

    local idx = 0
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            emit(idx,   x,   y);   emit(idx+1, x,   y+1); emit(idx+2, x+1, y)
            emit(idx+3, x+1, y);   emit(idx+4, x,   y+1); emit(idx+5, x+1, y+1)
            idx = idx + 6
        end
    end

    t = { bd = bd, vertCount = vertCount }
    templates[key] = t
    return t
end

function terrain:new(args)
    local self = setmetatable({}, terrain)
    local path     = args.path
    local quadSize = args.quadSize or 1.0

    local img = love.image.newImageData(path)
    local w, h = img:getDimensions()

    local tpl = getTemplate(w, h, quadSize)

    self.mesh = love.graphics.newMesh(format, tpl.bd, 'triangles', 'static')
    self.tex  = love.graphics.newImage(img)
    self.tex:setFilter('linear', 'linear')
    self.tex:setWrap('clamp')

    return self
end

function terrain:draw()
    love.graphics.draw(self.mesh)
end

return terrain
