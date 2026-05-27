require 'lib.FRAMELOOP'
require 'lib.overloads'
local ffi = require 'ffi'

-- ТЕСТ: async-заполнение меша по 2мс на кадр
local PATH = 'assets/maps/deathwingback_33_32_n.png'
local QUAD = 4.0
local HSCALE = 60.0
local BUDGET_MS = 2.0
local CHUNK_QUADS = 256  -- сколько квадов писать за раз перед проверкой времени

ffi.cdef[[ typedef struct { float x,y,z, u,v; } TVert; ]]

local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
}

local clock = LT.getTime

local t = clock()
local img = love.image.newImageData(PATH)
local w, h = img:getDimensions()
local px = ffi.cast('uint8_t*', img:getFFIPointer())
local tRead = (clock() - t) * 1000

t = clock()
local heights = ffi.new('float[?]', w * h)
local k = HSCALE / (3 * 255)
for i = 0, w * h - 1 do
    local p = i * 4
    heights[i] = (px[p] + px[p+1] + px[p+2]) * k
end
local tHeights = (clock() - t) * 1000

t = clock()
local vertCount = w * h * 6
local bytes = ffi.sizeof('TVert') * vertCount
local mesh = LG.newMesh(format, vertCount, 'triangles', 'dynamic')
local tNewMesh = (clock() - t) * 1000

t = clock()
local bd = love.data.newByteData(bytes)
local verts = ffi.cast('TVert*', bd:getFFIPointer())
local invW, invH = 1 / w, 1 / h
local tBdAlloc = (clock() - t) * 1000

local tFillTotal = 0  -- сумма времени fillStep по кадрам

-- состояние постепенного заполнения
local doneQuads = 0
local totalQuads = w * h
local startTime
local finished = false
local frames = 0

local function emit(i, x, y)
    local v = verts[i]
    local hx = x < w and x or w - 1
    local hy = y < h and y or h - 1
    v.x = x * QUAD
    v.y = heights[hy * w + hx]
    v.z = y * QUAD
    v.u = x * invW
    v.v = y * invH
end

local function fillStep(budgetMs)
    local t0 = LT.getTime()
    while doneQuads < totalQuads do
        local stop = math.min(doneQuads + CHUNK_QUADS, totalQuads)
        for q = doneQuads, stop - 1 do
            local x = q % w
            local y = math.floor(q / w)
            local idx = q * 6
            emit(idx,   x,   y);   emit(idx+1, x,   y+1); emit(idx+2, x+1, y)
            emit(idx+3, x+1, y);   emit(idx+4, x,   y+1); emit(idx+5, x+1, y+1)
        end
        doneQuads = stop
        if (LT.getTime() - t0) * 1000 >= budgetMs then break end
    end
    return (LT.getTime() - t0) * 1000
end

local camera = require 'class.camera':new{ x=512, y=200, z=1024, far=4096 }
local SHADER = LG.newShader[[
    uniform mat4 viewproj;
    uniform int  drawCount;
    #ifdef VERTEX
    vec4 position(mat4 _, vec4 p) { return viewproj * vec4(p.xyz, 1.0); }
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) { return vec4(uv, 0.5, 1.0); }
    #endif
]]

function love.update(dt)
    camera:update(dt)
    if not finished then
        if not startTime then startTime = LT.getTime() end
        frames = frames + 1
        local spent = fillStep(BUDGET_MS)
        tFillTotal = tFillTotal + spent
        if doneQuads >= totalQuads then
            local t = LT.getTime()
            mesh:setVertices(bd)
            local upload = (LT.getTime() - t) * 1000
            local total = (LT.getTime() - startTime) * 1000
            print(string.format(
                'read=%.2f  heights=%.2f  newMesh=%.2f  bdAlloc=%.2f  fill_sum=%.2f  upload=%.2f  | frames=%d  wall=%.2f',
                tRead, tHeights, tNewMesh, tBdAlloc, tFillTotal, upload, frames, total))
            finished = true
        else
            -- частичный апдейт чтобы видеть прогресс
            mesh:setVertices(bd)
        end
    end
end

function love.draw()
    LG.clear(0.05, 0.05, 0.08)
    LG.setDepthMode('lequal', true)
    LG.setShader(SHADER)
    SHADER:send('viewproj', camera:viewproj())
    -- рисуем только готовую часть
    mesh:setDrawRange(1, doneQuads * 6)
    LG.draw(mesh)
    LG.setShader()
    LG.setDepthMode()
    LG.print(string.format('quads %d / %d   frames %d   fps %s',
        doneQuads, totalQuads, frames, tostring(LT.realFPS)), 10, 10)
end

function love.wheelmoved(x,y) camera:wheelmoved(y) end
function love.mousemoved(x,y,dx,dy) camera:mousemoved(dx,dy) end
