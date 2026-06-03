require 'lib.overloads'

local Terrain = require 'class.terrain'
local Camera  = require 'class.camera'

local TILE = 533.33333
local MAP    = 'deathknightstart'
local ADT_DIR = 'assets/converted/world/maps/' .. MAP

local terrain = Terrain:new()
local cx, cy = terrain:loadDir(ADT_DIR)        -- грузим всю папку, центр блока для камеры
terrain:build()

-- камера над центром блока
local camera = Camera:new{
    x = (cx or 0) * TILE + TILE / 2, y = 0, z = (cy or 0) * TILE + TILE / 2,
    pitch = -0.6, near = 2, far = 4000, speed = 200,
}

function love.update(dt)
    camera:update(dt)
    terrain:update(dt)
end

function love.draw()
    LG.clear(0.5, 0.6, 0.75)
    terrain:draw(camera)
    LG.setShader(); LG.setDepthMode()
    LG.print(string.format('fps %d', love.timer.getFPS()), 10, 10)
end

function love.wheelmoved(x, y) camera:wheelmoved(y) end
function love.mousemoved(x, y, dx, dy) camera:mousemoved(dx, dy) end
function love.keypressed(k)
    if k == 'escape' then love.event.quit() end
end
